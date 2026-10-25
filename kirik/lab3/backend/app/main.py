"""REST API v1 для нескольких процессов: PostgreSQL, JWT и WebSocket push."""
import asyncio
import hashlib
import hmac
import json
import logging
import os
from datetime import datetime, timedelta, timezone
from contextlib import suppress
from email.utils import format_datetime, parsedate_to_datetime
from pathlib import Path
from uuid import UUID, uuid4

import jwt
from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.openapi.utils import get_openapi

from .push import PushHub
from .schemas import TaskCreate, TaskPatch, Login
from .storage import Database, password_hash

ROOT = Path(__file__).resolve().parents[1]
bearer = HTTPBearer(auto_error=False)


def now():
    return datetime.now(timezone.utc).isoformat(timespec='microseconds')


def task(row):
    result = dict(row)
    result.pop('owner', None)
    result['deleted'] = bool(result['deleted'])
    return result


def create_app(dsn=None, secret=None, release=None, instance=None):
    dsn = dsn or os.environ['DATABASE_URL']
    secret = secret or os.environ['JWT_SECRET']
    if len(secret) < 32:
        raise ValueError('JWT_SECRET должен иметь не менее 32 символов')
    release = release or json.loads((Path(__file__).parent / 'release.json').read_text())
    instance = instance or os.getenv('INSTANCE_ID', 'dev-1')
    db = Database(dsn)
    db.initialize()
    hub = PushHub(dsn)
    app = FastAPI(title='Учёт задач — лабораторная №3', version=release['version'], lifespan=hub.lifespan,
        description='Статус задачи. Для мутаций нужен Idempotency-Key; для PATCH/DELETE — If-Match с версией в кавычках.',
        responses={code: {'description': text} for code, text in {
            400: 'Некорректные данные', 401: 'Требуется вход', 403: 'Недостаточно прав',
            404: 'Запись не найдена', 409: 'Конфликт версии или ключа операции',
            415: 'Требуется application/json', 500: 'Внутренняя ошибка сервера'}.items()})
    app.state.db = db
    app.state.secret = secret
    app.state.hub = hub
    app.state.instance = instance

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        return JSONResponse(status_code=400, content={'detail': 'Некорректные поля запроса',
            'fields': [{'field': '.'.join(map(str, e['loc'])), 'message': e['msg']} for e in exc.errors()]})

    @app.exception_handler(Exception)
    async def unexpected_error(request, exc):
        logging.exception('Ошибка обработки API', exc_info=exc)
        return JSONResponse(status_code=500, content={'detail': 'Внутренняя ошибка сервера'})

    @app.middleware('http')
    async def headers(request, call_next):
        if request.method in ('POST', 'PATCH') and request.url.path.startswith('/api/'):
            if request.headers.get('content-type', '').split(';')[0].strip() != 'application/json':
                return JSONResponse(status_code=415, content={'detail': 'Требуется application/json'})
        response = await call_next(request)
        response.headers['X-Backend-ID'] = instance
        response.headers['X-App-Version'] = release['version']
        response.headers['X-Content-Type-Options'] = 'nosniff'
        if 'cache-control' not in response.headers:
            response.headers['Cache-Control'] = 'no-store'
        return response

    def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        try:
            if credentials is None:
                raise ValueError()
            payload = jwt.decode(credentials.credentials, secret, algorithms=['HS256'],
                                 options={'require': ['exp', 'sub']})
            with db.connect() as conn:
                row = conn.execute('SELECT * FROM users WHERE username=%s', (payload['sub'],)).fetchone()
            if row is None:
                raise ValueError()
            return dict(row)
        except (ValueError, jwt.PyJWTError):
            raise HTTPException(401, 'Войдите заново: токен отсутствует или истёк',
                                headers={'WWW-Authenticate': 'Bearer'})

    def writer(user=Depends(current_user)):
        if user['role'] != 'writer':
            raise HTTPException(403, 'Этому пользователю доступно только чтение')
        return user

    @app.get('/health')
    def health():
        return {'status': 'ok'}

    @app.get('/', include_in_schema=False)
    def browser():
        return FileResponse(ROOT / 'static' / 'index.html')

    @app.get('/browser.js', include_in_schema=False)
    def script():
        return FileResponse(ROOT / 'static' / 'browser.js', media_type='application/javascript')

    @app.post('/api/v1/auth/login')
    def login(body: Login):
        with db.connect() as conn:
            row = conn.execute('SELECT * FROM users WHERE username=%s', (body.username,)).fetchone()
        salt = row['salt'] if row else '00' * 16
        checked = password_hash(body.password, salt)
        if not row or not hmac.compare_digest(checked, row['password_hash']):
            raise HTTPException(401, 'Неправильное имя пользователя или пароль',
                                headers={'WWW-Authenticate': 'Bearer'})
        token = jwt.encode({'sub': row['username'], 'exp': datetime.now(timezone.utc) + timedelta(hours=8)},
                           secret, algorithm='HS256')
        return {'access_token': token, 'token_type': 'bearer', 'username': row['username']}

    def cached(request, records, single=False):
        # Валидатор зависит от содержимого, в том числе от tombstones и владельца URL-кэша.
        encoded = json.dumps(records, ensure_ascii=False, sort_keys=True)
        etag = '"' + hashlib.sha256(encoded.encode()).hexdigest() + '"'
        if single:
            etag = '"' + str(records[0]['version']) + '"'
        latest = max((r['updated_at'] for r in records), default='1970-01-01T00:00:00+00:00')
        modified = datetime.fromisoformat(latest).replace(microsecond=0)
        hdr = {'ETag': etag, 'Last-Modified': format_datetime(modified, usegmt=True),
               'Cache-Control': 'private, no-cache', 'Vary': 'Authorization'}
        match = request.headers.get('if-none-match')
        unchanged = match is not None and any(t.strip().removeprefix('W/') in (etag, '*') for t in match.split(','))
        # ETag имеет приоритет над датой. При нескольких записях за секунду IMS
        # не доказывает неизменность: используем строгое сравнение с полной датой.
        if match is None and request.headers.get('if-modified-since'):
            try:
                unchanged = datetime.fromisoformat(latest) <= parsedate_to_datetime(request.headers['if-modified-since'])
            except (ValueError, TypeError):
                pass
        if unchanged:
            return Response(status_code=304, headers=hdr)
        return JSONResponse(content=records[0] if single else records, headers=hdr)

    @app.get('/api/v1/tasks', responses={304: {'description': 'Кэш актуален, тело отсутствует'}})
    def listing(request: Request, include_deleted: bool = False, user=Depends(current_user)):
        with db.connect() as conn:
            rows = conn.execute('SELECT * FROM tasks WHERE owner=%s ORDER BY due_date DESC,id', (user['username'],)).fetchall()
        records = [task(r) for r in rows if include_deleted or not r['deleted']]
        return cached(request, records)

    def owned(conn, record_id, user):
        row = conn.execute('SELECT * FROM tasks WHERE id=%s FOR UPDATE', (str(record_id),)).fetchone()
        if row is None or row['owner'] != user['username']:
            raise HTTPException(404, 'Задача не найден')
        return row

    @app.get('/api/v1/tasks/{record_id}', responses={304: {'description': 'Кэш актуален, тело отсутствует'}})
    def get_one(record_id: UUID, request: Request, user=Depends(current_user)):
        with db.connect() as conn:
            row = owned(conn, record_id, user)
        if row['deleted']:
            raise HTTPException(404, 'Задача удалён')
        return cached(request, [task(row)], single=True)

    def replay(conn, key, fingerprint, user):
        if not key or len(key) > 128:
            raise HTTPException(400, 'Укажите Idempotency-Key длиной до 128 символов')
        # Один ключ сериализуется во всех backend. Повтор после потери ответа
        # увидит квитанцию, даже если первый запрос ещё выполняется.
        conn.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', (user['username'] + ':' + key,))
        row = conn.execute('SELECT * FROM operations WHERE owner=%s AND key=%s', (user['username'], key)).fetchone()
        if row:
            if row['fingerprint'] != fingerprint:
                raise HTTPException(409, 'Этот Idempotency-Key уже использован с другим запросом')
            return Response(status_code=204) if row['status'] == 204 else JSONResponse(json.loads(row['response']), status_code=row['status'])

    def receipt(conn, key, fingerprint, user, status, result):
        # NOTIFY относится к той же транзакции, что и задача/квитанция.
        # Повторы через replay не вызывают второе уведомление.
        record_id = result['id'] if result else fingerprint.split(':')[1]
        conn.execute('SELECT pg_notify(%s,%s)', ('tasks_changed', json.dumps({
            'type': 'task.changed', 'event_id': str(uuid4()), 'owner': user['username'],
            'record_id': record_id, 'action': fingerprint.split(':')[0],
            'instance': instance, 'version': release['version']})))
        conn.execute('INSERT INTO operations VALUES (%s,%s,%s,%s,%s)',
                     (user['username'], key, fingerprint, status, json.dumps(result)))
        return Response(status_code=204) if status == 204 else JSONResponse(result, status_code=status)

    @app.post('/api/v1/tasks', status_code=201)
    def create(body: TaskCreate, user=Depends(writer), idempotency_key: str = Header(default='')):
        values = body.model_dump(mode='json')
        fp = 'POST:' + json.dumps(values, sort_keys=True)
        with db.connect() as conn:
            old = replay(conn, idempotency_key, fp, user)
            if old is not None:
                return old
            conn.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,1))', (values['id'],))
            if conn.execute('SELECT 1 FROM tasks WHERE id=%s', (values['id'],)).fetchone():
                raise HTTPException(409, 'UUID уже существует')
            conn.execute('INSERT INTO tasks VALUES (%s,%s,%s,%s,%s,%s,%s,%s,0)',
                (values['id'], user['username'], values['due_date'], values['title'],
                 values['status'], values['description'], 1, now()))
            result = task(owned(conn, body.id, user))
            response = receipt(conn, idempotency_key, fp, user, 201, result)
            response.headers['Location'] = '/api/v1/tasks/' + values['id']
            return response

    def check_version(row, supplied):
        if supplied != '"' + str(row['version']) + '"':
            raise HTTPException(409, {'message': 'Запись изменилась на сервере', 'server': task(row)})

    @app.patch('/api/v1/tasks/{record_id}')
    def update(record_id: UUID, body: TaskPatch, user=Depends(writer),
               idempotency_key: str = Header(default=''), if_match: str = Header(default='')):
        changes = body.model_dump(mode='json', exclude_unset=True)
        if not changes or any(v is None for v in changes.values()):
            raise HTTPException(400, 'Передайте непустой набор полей без null')
        fp = f'PATCH:{record_id}:{if_match}:' + json.dumps(changes, sort_keys=True)
        with db.connect() as conn:
            old = replay(conn, idempotency_key, fp, user)
            if old is not None:
                return old
            row = owned(conn, record_id, user)
            check_version(row, if_match)
            if row['deleted']:
                raise HTTPException(409, {'message': 'Задача удалён на сервере', 'server': task(row)})
            merged = dict(row) | changes
            conn.execute('UPDATE tasks SET due_date=%s,title=%s,status=%s,description=%s,version=version+1,updated_at=%s WHERE id=%s',
                         (merged['due_date'], merged['title'], merged['status'], merged['description'], now(), str(record_id)))
            return receipt(conn, idempotency_key, fp, user, 200, task(owned(conn, record_id, user)))

    @app.delete('/api/v1/tasks/{record_id}', status_code=204)
    def delete(record_id: UUID, user=Depends(writer), idempotency_key: str = Header(default=''),
               if_match: str = Header(default='')):
        fp = f'DELETE:{record_id}:{if_match}'
        with db.connect() as conn:
            old = replay(conn, idempotency_key, fp, user)
            if old is not None:
                return old
            row = owned(conn, record_id, user)
            check_version(row, if_match)
            conn.execute('UPDATE tasks SET deleted=1,version=version+1,updated_at=%s WHERE id=%s', (now(), str(record_id)))
            return receipt(conn, idempotency_key, fp, user, 204, None)

    @app.get('/ready')
    def readiness():
        try:
            with db.connect() as conn:
                conn.execute('SELECT 1')
            if not hub.ready.is_set():
                raise RuntimeError('listener unavailable')
        except Exception:
            raise HTTPException(503, 'Экземпляр временно не готов')
        return {'status': 'ready', 'instance': instance, 'version': release['version']}

    @app.get('/meta')
    def metadata():
        return {'instance': instance, **release}

    if 'summary' in release.get('features', []):
        @app.get('/api/v1/summary')
        def summary(user=Depends(current_user)):
            with db.connect() as conn:
                row = conn.execute("SELECT count(*) AS count, COALESCE(sum(CASE WHEN status='done' THEN 1 ELSE 0 END),0) AS done FROM tasks WHERE owner=%s AND deleted=0", (user['username'],)).fetchone()
            return {'count': row['count'], 'done': int(row['done']), 'open': row['count'] - int(row['done'])}

    @app.websocket('/api/v1/events')
    async def events(websocket: WebSocket):
        # QML WebSocket авторизуется первым кадром; Python-клиент — заголовком.
        accepted = False
        try:
            auth = websocket.headers.get('authorization', '')
            if not auth:
                await websocket.accept()
                accepted = True
                frame = await asyncio.wait_for(websocket.receive_text(), timeout=8)
                if len(frame) > 4096:
                    raise ValueError()
                message = json.loads(frame)
                if message.get('type') != 'authenticate' or not isinstance(message.get('token'), str):
                    raise ValueError()
                auth = 'Bearer ' + message['token']
            if not auth.startswith('Bearer '):
                raise ValueError()
            claims = jwt.decode(auth[7:], secret, algorithms=['HS256'], options={'require': ['sub', 'exp']})
            # Синхронная проверка БД вынесена из event loop.
            await asyncio.to_thread(current_user, HTTPAuthorizationCredentials(scheme='Bearer', credentials=auth[7:]))
        except WebSocketDisconnect:
            return
        except (ValueError, jwt.PyJWTError, HTTPException, asyncio.TimeoutError, AttributeError):
            with suppress(RuntimeError):
                await websocket.close(code=1008)
            return
        if not accepted:
            await websocket.accept()
        queue = asyncio.Queue(maxsize=64)
        hub.clients[queue] = claims['sub']
        try:
            await websocket.send_json({'type': 'connected', 'instance': instance, 'version': release['version']})
            while True:
                if datetime.now(timezone.utc).timestamp() >= claims['exp']:
                    await websocket.close(code=1008, reason='token expired')
                    return
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=15)
                except asyncio.TimeoutError:
                    event = {'type': 'heartbeat'}
                await websocket.send_json(event)
        except (WebSocketDisconnect, RuntimeError, OSError):
            pass
        finally:
            hub.clients.pop(queue, None)

    def openapi():
        if app.openapi_schema is None:
            schema = get_openapi(title=app.title, version=app.version, description=app.description, routes=app.routes)
            # Стандартный FastAPI описывает 422, но наш обработчик возвращает 400.
            for path in schema['paths'].values():
                for operation in path.values():
                    if isinstance(operation, dict):
                        operation.get('responses', {}).pop('422', None)
            app.openapi_schema = schema
        return app.openapi_schema
    app.openapi = openapi
    return app
