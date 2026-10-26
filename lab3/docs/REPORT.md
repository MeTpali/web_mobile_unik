## ОТЧЁТ

## по лабораторной работе №3

## Сборка, подпись, деплой и масштабирование приложений Aurora OS

## Вариант №6 — Расходы

Данные титульного листа заполняются студентом.

## 1. Задание

Часть 1. Серверная инфраструктура на ПК или в облаке. Развернуть серверную часть из второй лабораторной или новую. Настроить автозапуск через systemd. Настроить nginx как reverse proxy. Запустить два или три экземпляра приложения через Docker или systemd-шаблоны. Реализовать балансировку нагрузки. Выполнить blue-green или канареечный деплой новой версии. Проверить отказоустойчивость, отключая один экземпляр и убеждаясь, что сервис продолжает работать.

Часть 2. Основная нативная часть на мобильном устройстве. Собрать RPM-пакет для Aurora OS с помощью rpmbuild. Подписать пакет сертификатом разработчика через sign_package. Установить подписанный RPM на реальный телефон. Настроить приложение на работу через балансировщик. Реализовать WebSockets для push-уведомлений. Реализовать проверку доступности серверов и повторные попытки. Проверить отказоустойчивость: отключить один backend и показать, что приложение продолжает работать. Продемонстрировать обновление версии без простоя через blue-green. Показать получение push-уведомления.

Вариант №6: Расходы. Сервер хранит расходы с полями дата, категория, сумма, комментарий. Приложение позволяет создавать, просматривать, редактировать и удалять расходы, работать offline и синхронизироваться.

## 2. Выполнение

За основу взят учёт расходов из второй лабораторной. FastAPI использует общую PostgreSQL; два процесса запускаются через systemd-шаблон. nginx завершает HTTPS и балансирует запросы. Подготовлены blue 1.0.2 и green 2.0.2: green добавляет /api/v1/summary. Клиент Qt/QML/C++ обновлён до версии 2.0.0 и подключается к одному адресу балансировщика.

Сохранены JWT, локальный SQLite-кэш и offline-очередь. Добавлен WSS-сервис с heartbeat и повторами; при уведомлении клиент выполняет REST-синхронизацию. Межпроцессные события передаются через PostgreSQL LISTEN/NOTIFY после COMMIT. Код отделён от настроек инфраструктуры, релизы хранятся в отдельных неизменяемых каталогах. RPM собран через mb2/rpmbuild и подписан штатным rpmsign-external через явную обёртку sign_package.sh.

Самостоятельное приложение «Расходы ЛР3» использует пакет com.example.expenseslab3. Оно устанавливается одновременно с клиентом другой лабораторной. QSettings, локальная SQLite-база и offline-очередь изолированы; данные прежнего пакета com.example.expenses автоматически не переносятся.

При expense.changed отдельный QML-компонент SystemNotification публикует штатное уведомление Авроры через Nemo.Notifications. Для POST/PATCH/DELETE заданы отдельные заголовки и preview-текст. Повторы и heartbeat отфильтрованы; следующие события заменяют одну запись. Приложение должно исполняться и поддерживать WSS; получение после полного закрытия не реализовано.

## 2.1. Основные файлы

## backend/app/schemas.py

Схемы JSON и правила валидации.

```
from datetime import date as Date
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

class Input(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)

class Login(Input):
    username: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=1, max_length=256)

class ExpenseFields(Input):
    date: Date
    category: str = Field(min_length=1, max_length=80)
    amount_minor: int = Field(strict=True, gt=0, le=1_000_000_000_00)
    comment: str = Field(default='', max_length=2000)

class ExpenseCreate(ExpenseFields):
    id: UUID

class ExpensePatch(Input):
    date: Date | None = None
    category: str | None = Field(default=None, min_length=1, max_length=80)
    amount_minor: int | None = Field(default=None, strict=True, gt=0, le=1_000_000_000_00)
    comment: str | None = Field(default=None, max_length=2000)
```

## backend/app/storage.py

Таблицы SQLite, транзакции и хеширование паролей.

```
import hashlib
import os
import secrets
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row

def password_hash(password: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 200_000).hex()

class Database:
    def __init__(self, dsn):
        self.dsn = dsn

    @contextmanager
    def connect(self):

        with psycopg.connect(self.dsn, row_factory=dict_row, connect_timeout=3,
                             options='-c statement_timeout=5000') as conn:
            yield conn

    def initialize(self):
        with self.connect() as db:

            db.execute('SELECT pg_advisory_xact_lock(73103001)')
            db.execute('''CREATE TABLE IF NOT EXISTS users (
                username TEXT PRIMARY KEY, salt TEXT NOT NULL,
                password_hash TEXT NOT NULL, role TEXT NOT NULL)''')
            db.execute('''CREATE TABLE IF NOT EXISTS expenses (
                id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES users(username),
                date TEXT NOT NULL, category TEXT NOT NULL, amount_minor BIGINT NOT NULL,
                comment TEXT NOT NULL, version INTEGER NOT NULL, updated_at TEXT NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0)''')
            db.execute('''CREATE TABLE IF NOT EXISTS operations (
                owner TEXT NOT NULL, key TEXT NOT NULL, fingerprint TEXT NOT NULL,
                status INTEGER NOT NULL, response TEXT, PRIMARY KEY(owner,key))''')
            for name, role in [('demo', 'writer'), ('viewer', 'reader')]:
                salt = secrets.token_hex(16)
                db.execute('INSERT INTO users VALUES (%s,%s,%s,%s) ON CONFLICT DO NOTHING',
                           (name, salt, password_hash(os.getenv('LAB_DEMO_PASSWORD', 'demo12345'), salt), role))
```

## backend/app/main.py

REST API v1, JWT, права доступа, версии, кэширование и повторы операций.

```
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
from .schemas import ExpenseCreate, ExpensePatch, Login
from .storage import Database, password_hash

ROOT = Path(__file__).resolve().parents[1]
bearer = HTTPBearer(auto_error=False)

def now():
    return datetime.now(timezone.utc).isoformat(timespec='microseconds')

def expense(row):
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
    app = FastAPI(title='Учёт расходов — лабораторная №3', version=release['version'], lifespan=hub.lifespan,
        description='Сумма в копейках. Для мутаций нужен Idempotency-Key; для PATCH/DELETE — If-Match с версией в кавычках.',
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

        if match is None and request.headers.get('if-modified-since'):
            try:
                unchanged = datetime.fromisoformat(latest) <= parsedate_to_datetime(request.headers['if-modified-since'])
            except (ValueError, TypeError):
                pass
        if unchanged:
            return Response(status_code=304, headers=hdr)
        return JSONResponse(content=records[0] if single else records, headers=hdr)

    @app.get('/api/v1/expenses', responses={304: {'description': 'Кэш актуален, тело отсутствует'}})
    def listing(request: Request, include_deleted: bool = False, user=Depends(current_user)):
        with db.connect() as conn:
            rows = conn.execute('SELECT * FROM expenses WHERE owner=%s ORDER BY date DESC,id', (user['username'],)).fetchall()
        records = [expense(r) for r in rows if include_deleted or not r['deleted']]
        return cached(request, records)

    def owned(conn, record_id, user):
        row = conn.execute('SELECT * FROM expenses WHERE id=%s FOR UPDATE', (str(record_id),)).fetchone()
        if row is None or row['owner'] != user['username']:
            raise HTTPException(404, 'Расход не найден')
        return row

    @app.get('/api/v1/expenses/{record_id}', responses={304: {'description': 'Кэш актуален, тело отсутствует'}})
    def get_one(record_id: UUID, request: Request, user=Depends(current_user)):
        with db.connect() as conn:
            row = owned(conn, record_id, user)
        if row['deleted']:
            raise HTTPException(404, 'Расход удалён')
        return cached(request, [expense(row)], single=True)

    def replay(conn, key, fingerprint, user):
        if not key or len(key) > 128:
            raise HTTPException(400, 'Укажите Idempotency-Key длиной до 128 символов')

        conn.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', (user['username'] + ':' + key,))
        row = conn.execute('SELECT * FROM operations WHERE owner=%s AND key=%s', (user['username'], key)).fetchone()
        if row:
            if row['fingerprint'] != fingerprint:
                raise HTTPException(409, 'Этот Idempotency-Key уже использован с другим запросом')
            return Response(status_code=204) if row['status'] == 204 else JSONResponse(json.loads(row['response']), status_code=row['status'])

    def receipt(conn, key, fingerprint, user, status, result):

        record_id = result['id'] if result else fingerprint.split(':')[1]
        conn.execute('SELECT pg_notify(%s,%s)', ('expenses_changed', json.dumps({
            'type': 'expense.changed', 'event_id': str(uuid4()), 'owner': user['username'],
            'record_id': record_id, 'action': fingerprint.split(':')[0],
            'instance': instance, 'version': release['version']})))
        conn.execute('INSERT INTO operations VALUES (%s,%s,%s,%s,%s)',
                     (user['username'], key, fingerprint, status, json.dumps(result)))
        return Response(status_code=204) if status == 204 else JSONResponse(result, status_code=status)

    @app.post('/api/v1/expenses', status_code=201)
    def create(body: ExpenseCreate, user=Depends(writer), idempotency_key: str = Header(default='')):
        values = body.model_dump(mode='json')
        fp = 'POST:' + json.dumps(values, sort_keys=True)
        with db.connect() as conn:
            old = replay(conn, idempotency_key, fp, user)
            if old is not None:
                return old
            conn.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,1))', (values['id'],))
            if conn.execute('SELECT 1 FROM expenses WHERE id=%s', (values['id'],)).fetchone():
                raise HTTPException(409, 'UUID уже существует')
            conn.execute('INSERT INTO expenses VALUES (%s,%s,%s,%s,%s,%s,%s,%s,0)',
                (values['id'], user['username'], values['date'], values['category'],
                 values['amount_minor'], values['comment'], 1, now()))
            result = expense(owned(conn, body.id, user))
            response = receipt(conn, idempotency_key, fp, user, 201, result)
            response.headers['Location'] = '/api/v1/expenses/' + values['id']
            return response

    def check_version(row, supplied):
        if supplied != '"' + str(row['version']) + '"':
            raise HTTPException(409, {'message': 'Запись изменилась на сервере', 'server': expense(row)})

    @app.patch('/api/v1/expenses/{record_id}')
    def update(record_id: UUID, body: ExpensePatch, user=Depends(writer),
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
                raise HTTPException(409, {'message': 'Расход удалён на сервере', 'server': expense(row)})
            merged = dict(row) | changes
            conn.execute('UPDATE expenses SET date=%s,category=%s,amount_minor=%s,comment=%s,version=version+1,updated_at=%s WHERE id=%s',
                         (merged['date'], merged['category'], merged['amount_minor'], merged['comment'], now(), str(record_id)))
            return receipt(conn, idempotency_key, fp, user, 200, expense(owned(conn, record_id, user)))

    @app.delete('/api/v1/expenses/{record_id}', status_code=204)
    def delete(record_id: UUID, user=Depends(writer), idempotency_key: str = Header(default=''),
               if_match: str = Header(default='')):
        fp = f'DELETE:{record_id}:{if_match}'
        with db.connect() as conn:
            old = replay(conn, idempotency_key, fp, user)
            if old is not None:
                return old
            row = owned(conn, record_id, user)
            check_version(row, if_match)
            conn.execute('UPDATE expenses SET deleted=1,version=version+1,updated_at=%s WHERE id=%s', (now(), str(record_id)))
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
                row = conn.execute('SELECT count(*) AS count, COALESCE(sum(amount_minor),0) AS total_minor FROM expenses WHERE owner=%s AND deleted=0', (user['username'],)).fetchone()
            return {'count': row['count'], 'total_minor': int(row['total_minor'])}

    @app.websocket('/api/v1/events')
    async def events(websocket: WebSocket):

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

            for path in schema['paths'].values():
                for operation in path.values():
                    if isinstance(operation, dict):
                        operation.get('responses', {}).pop('422', None)
            app.openapi_schema = schema
        return app.openapi_schema
    app.openapi = openapi
    return app
```

## backend/app/push.py

PostgreSQL LISTEN/NOTIFY и доставка событий своим WebSocket-клиентам.

```
import asyncio
import json
import logging
from contextlib import asynccontextmanager, suppress

import psycopg

class PushHub:
    def __init__(self, dsn):
        self.dsn = dsn
        self.clients = {}
        self.ready = asyncio.Event()

    def deliver(self, event):
        for queue, owner in list(self.clients.items()):
            if event.get('owner') not in (None, owner):
                continue
            public = {k: v for k, v in event.items() if k != 'owner'}
            if queue.full():

                while not queue.empty():
                    queue.get_nowait()
                public = {'type': 'resync'}
            queue.put_nowait(public)

    async def listen(self):
        while True:
            try:
                async with await psycopg.AsyncConnection.connect(self.dsn, autocommit=True,
                        connect_timeout=3, keepalives=1, keepalives_idle=10,
                        keepalives_interval=3, keepalives_count=3) as conn:
                    await conn.execute('LISTEN expenses_changed')
                    self.ready.set()

                    self.deliver({'type': 'resync'})
                    async for notification in conn.notifies():
                        try:
                            self.deliver(json.loads(notification.payload))
                        except (ValueError, TypeError):
                            logging.exception('Некорректное межпроцессное событие')
            except asyncio.CancelledError:
                raise
            except psycopg.Error:
                self.ready.clear()
                logging.exception('LISTEN временно недоступен; повтор через 2 секунды')
                await asyncio.sleep(2)

    @asynccontextmanager
    async def lifespan(self, app):
        task = asyncio.create_task(self.listen())
        try:
            await asyncio.wait_for(self.ready.wait(), timeout=10)
            yield
        finally:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task
```

## backend/app/entry.py

Точка входа systemd-инстанса.

```
from .main import create_app

app = create_app()
```

## backend/static/index.html

Адаптивная вспомогательная браузерная форма.

```
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Учёт расходов — REST API</title>
  <style>
    body{font:17px sans-serif;max-width:850px;margin:auto;padding:18px;background:#f1f5f9;color:#152535}
    section{background:white;padding:18px;border-radius:12px;margin:14px 0}label{display:block;margin:10px 0}
    input,textarea,button{box-sizing:border-box;font:inherit;padding:10px;max-width:100%}input,textarea{width:100%}
    button{margin:5px;min-height:44px}pre{white-space:pre-wrap;overflow-wrap:anywhere}li{padding:12px 0}
    @media(max-width:500px){body{padding:8px}section{padding:12px}button{width:100%;margin:5px 0}}
  </style>
</head>
<body>
  <h1>Учёт расходов</h1>
  <p>Тестовая страница REST API v1. Все ресурсы загружаются с этого сервера. <a href="/docs">Swagger UI</a></p>
  <section>
    <h2>Вход</h2>
    <form id="login"><label>Пользователь<input id="username" value="demo" required autocomplete="username"></label>
      <label>Пароль<input id="password" type="password" required autocomplete="current-password"></label>
      <button>Войти</button><button type="button" id="logout">Выйти</button></form>
  </section>
  <section>
    <h2>Создать или изменить расход</h2>
    <form id="expense"><input id="recordId" type="hidden"><input id="version" type="hidden">
      <label>Дата<input id="date" type="date" required></label>
      <label>Категория<input id="category" maxlength="80" required></label>
      <label>Сумма, руб.<input id="amount" type="text" inputmode="decimal" placeholder="125.50" required></label>
      <label>Комментарий<textarea id="comment" maxlength="2000"></textarea></label>
      <button>Сохранить</button><button type="button" id="reset">Очистить форму</button>
    </form>
  </section>
  <section><h2>Расходы</h2><button id="refresh">Обновить список</button><ul id="list"></ul></section>
  <section><h2>Последний HTTP-ответ</h2><pre id="status" role="status">Войдите в систему.</pre></section>
  <script src="/browser.js"></script>
</body></html>
```

## backend/static/browser.js

Вход и браузерный CRUD через XMLHttpRequest.

```
(function () {
  'use strict';
  var token = '', busy = false;
  function el(id) { return document.getElementById(id); }
  function uuid() {
    var bytes = new Uint8Array(16);
    window.crypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    var hex = [];
    for (var i = 0; i < 16; i++) hex.push(('0' + bytes[i].toString(16)).slice(-2));
    return hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-' + hex.slice(6, 8).join('') + '-' + hex.slice(8, 10).join('') + '-' + hex.slice(10).join('');
  }
  function request(method, path, data, version, callback) {
    if (busy) { el('status').textContent = 'Дождитесь завершения запроса'; return; }
    busy = true;
    var xhr = new XMLHttpRequest();
    xhr.open(method, '/api/v1/' + path); xhr.timeout = 10000;
    xhr.setRequestHeader('Accept', 'application/json');
    if (token) xhr.setRequestHeader('Authorization', 'Bearer ' + token);
    if (data) xhr.setRequestHeader('Content-Type', 'application/json');
    if (method !== 'GET') xhr.setRequestHeader('Idempotency-Key', uuid());
    if (version) xhr.setRequestHeader('If-Match', '"' + version + '"');
    xhr.onload = function () {
      busy = false;
      var body = null;
      try { body = xhr.responseText ? JSON.parse(xhr.responseText) : null; } catch (e) {                                       }
      el('status').textContent = method + ' ' + path + '\nHTTP ' + xhr.status + '\n' + xhr.getAllResponseHeaders() + '\n' + xhr.responseText;
      if (xhr.status >= 200 && xhr.status < 300 && callback) callback(body);
    };
    xhr.onerror = xhr.ontimeout = function () { busy = false; el('status').textContent = 'Нет связи, ошибка TLS или тайм-аут. Обновите список перед повтором операции.'; };
    xhr.send(data ? JSON.stringify(data) : null);
  }
  function clear() { el('expense').reset(); el('recordId').value = ''; el('version').value = ''; el('date').value = new Date().toISOString().slice(0, 10); }
  function refresh() {
    request('GET', 'expenses', null, null, function (rows) {
      el('list').textContent = '';
      rows.forEach(function (row) {
        var li = document.createElement('li');
        var text = document.createElement('div');
        text.textContent = row.date + ' · ' + row.category + ' · ' + (row.amount_minor / 100).toFixed(2) + ' руб. · ' + row.comment;
        li.appendChild(text);
        var edit = document.createElement('button'); edit.textContent = 'Изменить';
        edit.onclick = function () {
          el('recordId').value = row.id; el('version').value = row.version;
          el('date').value = row.date; el('category').value = row.category;
          el('amount').value = (row.amount_minor / 100).toFixed(2); el('comment').value = row.comment;
          el('expense').scrollIntoView();
        };
        var remove = document.createElement('button'); remove.textContent = 'Удалить';
        remove.onclick = function () { if (window.confirm('Удалить расход?')) request('DELETE', 'expenses/' + row.id, null, row.version, refresh); };
        li.appendChild(edit); li.appendChild(remove); el('list').appendChild(li);
      });
    });
  }
  el('login').onsubmit = function (event) {
    event.preventDefault();
    request('POST', 'auth/login', {username: el('username').value, password: el('password').value}, null, function (body) {
      token = body.access_token; el('password').value = ''; refresh();
    });
  };
  el('expense').onsubmit = function (event) {
    event.preventDefault();
    var value = el('amount').value.trim().replace(',', '.');
    if (!/^\d+(\.\d{1,2})?$/.test(value)) { el('status').textContent = 'Введите положительную сумму с точностью до копеек'; return; }
    var parts = value.split('.');
    var data = {date: el('date').value, category: el('category').value,
      amount_minor: Number(parts[0]) * 100 + Number(((parts[1] || '') + '00').slice(0, 2)), comment: el('comment').value};
    var id = el('recordId').value;
    if (!id) data.id = uuid();
    request(id ? 'PATCH' : 'POST', id ? 'expenses/' + id : 'expenses', data, el('version').value, function () { clear(); refresh(); });
  };
  el('logout').onclick = function () { token = ''; el('list').textContent = ''; clear(); el('status').textContent = 'Вы вышли'; };
  el('refresh').onclick = refresh; el('reset').onclick = clear; clear();
}());
```

## client/src/pushservice.h

Интерфейс WSS-сервиса.

```
#pragma once
#include <QObject>
#include <QTimer>
#include <QElapsedTimer>
#include <QJsonObject>
#include <QSet>
#include <QQmlEngine>
#include <QSslConfiguration>

class PushService : public QObject {
    Q_OBJECT
public:
    explicit PushService(QObject *parent = nullptr);
    ~PushService() override;
    void start(const QString &url, const QString &token, const QString &certificate);
    void stop();
signals:
    void connected();
    void eventReceived(QJsonObject event);
    void statusChanged(QString status);
private slots:
    void receive(QString message);
    void schedule();
private:
    QQmlEngine *engine;
    QObject *socket = nullptr;
    QSslConfiguration initialSsl;
    QTimer retry, deadline, watchdog;
    QElapsedTimer lastMessage;
    QSet<QString> seen;
    QString baseUrl, authToken, certificatePath;
    bool wanted = false;
    int backoff = 1000;
    void open();
    void disposeSocket();
};
```

## client/src/pushservice.cpp

Подключение, heartbeat, безопасное завершение и повторы WSS.

```
#include "pushservice.h"
#include <QJsonDocument>
#include <QQmlComponent>
#include <QSslCertificate>
#include <QUrl>
#include <QCoreApplication>
#include <QPointer>

namespace {
QQmlEngine *sharedEngine() {

    static QQmlEngine *engine = new QQmlEngine(QCoreApplication::instance());
    return engine;
}
QObject *sharedTransport(QQmlEngine *engine, QString &error) {

    static QPointer<QObject> transport;
    if (!transport) {
        QQmlComponent component(engine, QUrl("qrc:/services/PushSocket.qml"));
        transport = component.create();
        if (!transport) { error = component.errorString(); return nullptr; }
        QQmlEngine::setObjectOwnership(transport, QQmlEngine::CppOwnership);
        transport->setParent(engine);
    }
    return transport;
}
}

PushService::PushService(QObject *parent) : QObject(parent), engine(sharedEngine()),
    initialSsl(QSslConfiguration::defaultConfiguration()) {
    retry.setSingleShot(true); deadline.setSingleShot(true);
    watchdog.setInterval(5000);
    connect(&retry, &QTimer::timeout, this, &PushService::open);
    connect(&deadline, &QTimer::timeout, this, [this]() { disposeSocket(); schedule(); });
    connect(&watchdog, &QTimer::timeout, this, [this]() {
        if (lastMessage.isValid() && lastMessage.elapsed() > 35000) { disposeSocket(); schedule(); }
    });
}
PushService::~PushService() {

    wanted = false; retry.stop(); deadline.stop(); watchdog.stop();
    disposeSocket();
}
void PushService::disposeSocket() {
    if (socket) {
        socket->disconnect(this);
        socket->setProperty("active", false);
        socket = nullptr;
    }
}
void PushService::stop() {
    wanted = false; retry.stop(); deadline.stop(); watchdog.stop();
    disposeSocket(); seen.clear();
    emit statusChanged("Push отключён");
}
void PushService::start(const QString &url, const QString &token, const QString &certificate) {
    if (wanted && baseUrl == url && authToken == token && certificatePath == certificate) return;
    stop(); baseUrl = url; authToken = token; certificatePath = certificate;
    wanted = true; backoff = 1000;

    retry.start(50);
}
void PushService::schedule() {
    deadline.stop(); watchdog.stop();
    if (!wanted || retry.isActive()) return;
    emit statusChanged(QString("Нет push-соединения. Повтор через %1 с").arg(backoff / 1000));
    retry.start(backoff); backoff = qMin(backoff * 2, 30000);
}
void PushService::open() {
    if (!wanted) return;
    disposeSocket();
    auto ssl = initialSsl;
    auto certs = ssl.caCertificates(); certs.append(QSslCertificate::fromPath(certificatePath));
    ssl.setCaCertificates(certs);

    QSslConfiguration::setDefaultConfiguration(ssl);
    QString error;
    socket = sharedTransport(engine, error);
    if (!socket) {
        emit statusChanged("QtWebSockets недоступен: " + error);
        schedule(); return;
    }
    connect(socket, SIGNAL(textReceived(QString)), this, SLOT(receive(QString)));
    connect(socket, SIGNAL(lost()), this, SLOT(schedule()));
    QUrl url(baseUrl); url.setScheme("wss"); url.setPath("/api/v1/events");
    socket->setProperty("url", url.toString());
    socket->setProperty("token", authToken);
    emit statusChanged("Подключение push…");
    deadline.start(10000); socket->setProperty("active", true);
}
void PushService::receive(QString message) {
    lastMessage.restart();
    const auto doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject()) return;
    const auto event = doc.object();
    if (event.value("type") == "connected") {
        deadline.stop(); backoff = 1000; lastMessage.start(); watchdog.start();
        emit statusChanged("Push: " + event.value("instance").toString() + " · v" + event.value("version").toString());
        emit connected(); return;
    }
    if (event.value("type") != "expense.changed" && event.value("type") != "resync") return;
    const auto id = event.value("event_id").toString();
    if (!id.isEmpty()) {
        if (seen.contains(id)) return;
        if (seen.size() >= 128) seen.clear();
        seen.insert(id);
    }
    emit eventReceived(event);
}
```

## client/services/PushSocket.qml

Нативный QtWebSockets-адаптер.

```
import QtQml 2.2
import QtWebSockets 1.0

QtObject {
    id: transport
    property string url
    property string token
    property bool active: false
    signal textReceived(string text)
    signal lost()
    property WebSocket connection: WebSocket {
        url: transport.url
        active: transport.active
        onStatusChanged: {
            if (status === WebSocket.Open) sendTextMessage(JSON.stringify({type: "authenticate", token: transport.token}))
            else if ((status === WebSocket.Error || status === WebSocket.Closed) && transport.active) transport.lost()
        }
        onTextMessageReceived: transport.textReceived(message)
    }
}
```

## client/qml/services/SystemNotification.qml

Системное уведомление при WSS-событии, защита от повторов и замена предыдущей записи.

```
import QtQml 2.2
import Nemo.Notifications 1.0

Notification {
    id: notification
    property var controller: null
    property var seen: []
    property int publishedCount: 0
    property string lastEventId: ""
    appName: "Расходы ЛР3"
    appIcon: "com.example.expenseslab3"
    expireTimeout: -1
    isTransient: false

    function notifyExpense(event) {
        var titles = {POST: "Расход добавлен", PATCH: "Расход изменён", DELETE: "Расход удалён"}
        if (!event || event.type !== "expense.changed" || !titles[event.action]) return
        if (event.event_id && seen.indexOf(event.event_id) !== -1) return
        summary = titles[event.action]
        body = "Изменения получены с сервера. Список расходов обновляется."
        previewSummary = summary
        previewBody = body
        timestamp = new Date()

        publish()
        if (replacesId) {
            lastEventId = event.event_id || ""
            if (lastEventId) {
                if (seen.length >= 128) seen.shift()
                seen.push(lastEventId)
            }
            publishedCount += 1
            console.info("System notification published: " + replacesId + " " + event.action)
        } else console.warn("Notification manager did not return an ID")
    }

    property Connections subscription: Connections {
        target: notification.controller
        onExpenseChanged: notification.notifyExpense(event)
    }
}
```

## deploy/systemd/expenses@.service

Автозапуск, restart и ограничения процессов.

```
[Unit]
Description=Expenses backend %i
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=expenseslab
Group=expenseslab
WorkingDirectory=/opt/expenses-lab/instances/%i/backend
EnvironmentFile=/etc/expenses-lab/common.env
EnvironmentFile=/etc/expenses-lab/%i.env
Environment=INSTANCE_ID=%i
ExecStart=/opt/expenses-lab/venv/bin/python -m uvicorn app.entry:app --host 127.0.0.1 --port ${PORT} --proxy-headers --forwarded-allow-ips 127.0.0.1 --timeout-graceful-shutdown 15 --ws websockets --ws-per-message-deflate false --ws-max-size 4096 --ws-ping-interval 15 --ws-ping-timeout 15
Restart=on-failure
RestartSec=2
KillSignal=SIGINT
TimeoutStopSec=25
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
UMask=0077

[Install]
WantedBy=multi-user.target
```

## deploy/nginx/expenses.conf

HTTPS, балансировщик, заголовки и WSS-проксирование.

```
include /etc/nginx/expenses-lab/active.conf;
map $http_upgrade $expenses_connection_upgrade {
    default upgrade;
    '' close;
}
log_format expenses_lab '$time_iso8601 $request_method $uri status=$status '
                        'upstream=$upstream_addr backend=$upstream_http_x_backend_id '
                        'version=$upstream_http_x_app_version';

server {
    listen 9443 ssl;
    server_name _;
    ssl_certificate /etc/expenses-lab/server.crt;
    ssl_certificate_key /etc/expenses-lab/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 64k;
    access_log /var/log/nginx/expenses-lab.log expenses_lab;

    location / {
        proxy_pass http://expenses_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $expenses_connection_upgrade;
        proxy_connect_timeout 1s;
        proxy_read_timeout 45s;
        proxy_send_timeout 10s;
        proxy_buffering off;

        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 2;
    }
}
```

## deploy/nginx/blue.conf

Два backend версии blue.

```
upstream expenses_backend {
    server 127.0.0.1:9101 max_fails=1 fail_timeout=3s;
    server 127.0.0.1:9102 max_fails=1 fail_timeout=3s;
}
```

## deploy/nginx/green.conf

Два backend версии green.

```
upstream expenses_backend {
    server 127.0.0.1:9201 max_fails=1 fail_timeout=3s;
    server 127.0.0.1:9202 max_fails=1 fail_timeout=3s;
}
```

## deploy/scripts/install-host.sh

Установка служб, общей БД и nginx с отдельными секретами.

```
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Запустите: sudo bash deploy/scripts/install-host.sh'; exit 1; }
lab_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
for lab_tool in nginx psql python3 openssl; do command -v "$lab_tool" >/dev/null; done
[[ -f "$lab_root/certificates/server.crt" && -f "$lab_root/certificates/server.key" ]] || {
    echo 'Сначала создайте certificates/server.crt и server.key по README.'; exit 1;
}
id expenseslab >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/expenses-lab --shell /usr/sbin/nologin expenseslab
install -d -m 755 /opt/expenses-lab/releases /opt/expenses-lab/instances /etc/nginx/expenses-lab
install -d -m 750 -o root -g expenseslab /etc/expenses-lab
if [[ ! -f /etc/expenses-lab/common.env ]]; then
    lab_db_password=$(openssl rand -hex 24)
    lab_jwt_secret=$(openssl rand -hex 32)
    printf 'DATABASE_URL=postgresql://expenses_lab:%s@127.0.0.1:5432/expenses_lab\nJWT_SECRET=%s\n' \
        "$lab_db_password" "$lab_jwt_secret" > /etc/expenses-lab/common.env
    chown root:expenseslab /etc/expenses-lab/common.env
    chmod 640 /etc/expenses-lab/common.env
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -v lab_password="$lab_db_password" <<'SQL'
SELECT format('CREATE ROLE expenses_lab LOGIN PASSWORD %L', :'lab_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='expenses_lab') \gexec
SELECT 'CREATE DATABASE expenses_lab OWNER expenses_lab'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='expenses_lab') \gexec
SQL
fi
python3 -m venv /opt/expenses-lab/venv
/opt/expenses-lab/venv/bin/python -m pip install -r "$lab_root/backend/requirements.txt"
for lab_release in 1.0.0 2.0.0; do
    lab_dir="/opt/expenses-lab/releases/$lab_release"
    if [[ ! -d "$lab_dir" ]]; then
        install -d "$lab_dir/backend"
        cp -r "$lab_root/backend/app" "$lab_root/backend/static" "$lab_dir/backend/"
        if [[ $lab_release == 1.0.0 ]]; then lab_features='[]'; else lab_features='["summary"]'; fi
        printf '{"version":"%s","features":%s}\n' "$lab_release" "$lab_features" > "$lab_dir/backend/app/release.json"
    fi
done
for lab_color in blue green; do
    if [[ $lab_color == blue ]]; then lab_version=1.0.0; lab_port=9100; else lab_version=2.0.0; lab_port=9200; fi
    for lab_number in 1 2; do
        lab_name="$lab_color-$lab_number"
        ln -sfn "/opt/expenses-lab/releases/$lab_version" "/opt/expenses-lab/instances/$lab_name"
        printf 'PORT=%s\n' "$((lab_port + lab_number))" > "/etc/expenses-lab/$lab_name.env"
    done
done
install -m 600 "$lab_root/certificates/server.key" /etc/expenses-lab/server.key
install -m 644 "$lab_root/certificates/server.crt" /etc/expenses-lab/server.crt
install -m 644 "$lab_root/deploy/systemd/expenses@.service" /etc/systemd/system/expenses@.service
install -m 644 "$lab_root/deploy/nginx/blue.conf" /etc/nginx/expenses-lab/blue.conf
install -m 644 "$lab_root/deploy/nginx/green.conf" /etc/nginx/expenses-lab/green.conf
[[ -L /etc/nginx/expenses-lab/active.conf ]] || ln -s blue.conf /etc/nginx/expenses-lab/active.conf
install -m 644 "$lab_root/deploy/nginx/expenses.conf" /etc/nginx/sites-available/expenses-lab.conf
ln -sfn /etc/nginx/sites-available/expenses-lab.conf /etc/nginx/sites-enabled/expenses-lab.conf
systemctl daemon-reload
systemctl enable --now expenses@blue-1 expenses@blue-2
for lab_port in 9101 9102; do
    lab_ready=false
    for lab_attempt in {1..30}; do
        if curl -fsS --max-time 2 "http://127.0.0.1:$lab_port/ready" >/dev/null; then lab_ready=true; break; fi
        sleep 1
    done
    $lab_ready || { echo "Инстанс на $lab_port не готов: journalctl -u expenses@blue-1 -u expenses@blue-2"; exit 1; }
done
nginx -t
systemctl enable nginx postgresql
systemctl reload nginx
echo 'Готово: два blue backend, nginx HTTPS :9443, общая PostgreSQL.'
```

## deploy/scripts/exercise-cluster.py

Реальная проверка отказа, blue-green, отката и push под нагрузкой.

```
import json
import os
import ssl
import subprocess
import threading
import time
from collections import Counter
from pathlib import Path
from uuid import uuid4

import httpx
from websockets.sync.client import connect

ROOT = Path(__file__).resolve().parents[2]
TLS = ssl.create_default_context(cafile=str(ROOT / 'certificates/server.crt'))
URL = 'https://127.0.0.1:9443'

def wait(condition, message, timeout=40):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if condition():
            return
        time.sleep(0.15)
    raise AssertionError(message)

def service(action, *names):
    subprocess.run(['systemctl', action, *['expenses@' + n for n in names]], check=True)

def switch(color):
    subprocess.run(['bash', str(ROOT / 'deploy/scripts/switch-release.sh'), color], check=True)

def main():
    if os.geteuid() != 0:
        raise SystemExit('Требуется sudo: тест останавливает и запускает только expenses@*.service')
    switch('blue')
    stop = threading.Event()
    counts, failures, events, connections, notifications = Counter(), [], [], [], []
    h = {}
    with httpx.Client(verify=TLS, timeout=6, trust_env=False) as c:
        login = c.post(URL + '/api/v1/auth/login', json={'username': 'demo', 'password': 'demo12345'})
        login.raise_for_status()
        h['Authorization'] = 'Bearer ' + login.json()['access_token']

        def monitor():
            with httpx.Client(verify=TLS, timeout=5, trust_env=False) as client:
                while not stop.is_set():
                    try:
                        r = client.get(URL + '/api/v1/expenses', headers=h)
                        r.raise_for_status()
                        backend = r.headers['x-backend-id'] + ' v' + r.headers['x-app-version']
                        counts[backend] += 1
                        events.append({'time': time.time(), 'backend': backend, 'status': r.status_code})
                    except Exception as exc:
                        failures.append(str(exc))
                    stop.wait(0.1)

        def watch():
            while not stop.is_set():
                try:
                    with connect('wss://127.0.0.1:9443/api/v1/events', ssl=TLS, additional_headers=h,
                                 open_timeout=5, close_timeout=2) as ws:
                        connected = json.loads(ws.recv(timeout=6))
                        connections.append(connected)
                        while not stop.is_set():
                            try:
                                value = json.loads(ws.recv(timeout=1))
                                if value.get('type') == 'expense.changed':
                                    notifications.append(value)
                            except TimeoutError:
                                pass
                except Exception:
                    stop.wait(0.5)

        threads = [threading.Thread(target=monitor), threading.Thread(target=watch)]
        for t in threads:
            t.start()
        ids = []

        def create():
            data = {'id': str(uuid4()), 'date': '2026-10-25', 'category': 'Deployment test',
                    'amount_minor': 101, 'comment': 'temporary'}
            r = c.post(URL + '/api/v1/expenses', json=data, headers=h | {'Idempotency-Key': str(uuid4())})
            r.raise_for_status(); ids.append(data['id'])
            wait(lambda: any(e['record_id'] == data['id'] for e in notifications), 'Не получен push после мутации')
            return data['id']

        try:
            wait(lambda: bool(connections) and sum(counts.values()) >= 10, 'Нет исходного WebSocket/HTTPS')
            initial_node = connections[-1]['instance']
            print('Отключаем backend WebSocket:', initial_node, flush=True)
            service('stop', initial_node)
            wait(lambda: connections[-1]['instance'] != initial_node, 'WebSocket не переподключился')
            before = sum(counts.values())
            wait(lambda: sum(counts.values()) >= before + 20, 'REST не работает после отказа')
            create()
            service('start', initial_node)
            port = 9101 if initial_node == 'blue-1' else 9102
            def ready():
                try:
                    return c.get(f'http://127.0.0.1:{port}/ready').status_code == 200
                except httpx.HTTPError:
                    return False
            wait(ready, 'Отключённый backend не восстановился')
            print('Переключаем blue → green', flush=True)
            switch('green')
            wait(lambda: c.get(URL + '/meta').json()['version'].startswith('2.'), 'Нет новой версии')

            assert c.get(URL + '/api/v1/summary', headers=h).status_code == 200
            service('stop', 'blue-1', 'blue-2')
            wait(lambda: connections[-1]['instance'].startswith('green'), 'WS остался на остановленной группе')
            create()
            before = sum(counts.values())
            wait(lambda: sum(counts.values()) >= before + 20, 'Нет запросов к green')
            print('Откат green → blue', flush=True)
            switch('blue')
            wait(lambda: c.get(URL + '/meta').json()['version'].startswith('1.'), 'Откат не выполнен')
            assert c.get(URL + '/api/v1/summary', headers=h).status_code == 404
            service('stop', 'green-1', 'green-2')
            wait(lambda: connections[-1]['instance'].startswith('blue'), 'WS не восстановился после отката')
            create()
        finally:

            switch('blue')
            for record_id in ids:
                url = URL + '/api/v1/expenses/' + record_id
                r = c.get(url, headers=h)
                if r.status_code == 200:
                    c.delete(url, headers=h | {'If-Match': f'"{r.json()["version"]}"', 'Idempotency-Key': str(uuid4())})
            stop.set()
            for t in threads:
                t.join(timeout=10)
    result = {'requests': sum(counts.values()), 'backends': dict(counts), 'failures': failures,
              'ws_connections': connections, 'push_events': notifications, 'events': events}
    path = ROOT / 'docs/cluster-validation.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    if os.getenv('SUDO_UID'):
        os.chown(path.parent, int(os.environ['SUDO_UID']), int(os.environ['SUDO_GID']))
        os.chown(path, int(os.environ['SUDO_UID']), int(os.environ['SUDO_GID']))
    print(json.dumps({k: v for k, v in result.items() if k != 'events'}, ensure_ascii=False, indent=2))
    assert not failures, 'Во время демонстрации были неуспешные HTTPS-запросы'
    print('PASS: failover, push reconnect, blue-green, rollback, no HTTP downtime')

if __name__ == '__main__':
    main()
```

## deploy/scripts/stage-release.sh

Создание неизменяемого релиза.

```
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Нужен sudo'; exit 1; }
lab_color=${1:?blue или green}
lab_version=${2:?Номер новой версии}
[[ $lab_color == blue || $lab_color == green ]] || exit 2
[[ $lab_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
lab_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
if [[ -n ${SUDO_UID:-} && -d "$lab_root/docs" ]]; then
    chown "$SUDO_UID:$SUDO_GID" "$lab_root/docs"
fi
lab_dir="/opt/expenses-lab/releases/$lab_version"
[[ ! -e "$lab_dir" ]] || { echo "Версия $lab_version уже существует: выберите новый номер"; exit 1; }
exec 9>/run/lock/expenses-release.lock
flock 9
install -m 644 "$lab_root/deploy/systemd/expenses@.service" /etc/systemd/system/expenses@.service
systemctl daemon-reload
install -d "$lab_dir/backend"
cp -r "$lab_root/backend/app" "$lab_root/backend/static" "$lab_dir/backend/"
if [[ $lab_color == green ]]; then lab_features='["summary"]'; lab_base=9200; else lab_features='[]'; lab_base=9100; fi
printf '{"version":"%s","features":%s}\n' "$lab_version" "$lab_features" > "$lab_dir/backend/app/release.json"
for lab_number in 1 2; do
    ln -sfn "$lab_dir" "/opt/expenses-lab/instances/$lab_color-$lab_number"
    systemctl restart "expenses@$lab_color-$lab_number"
    lab_ok=false
    for lab_attempt in {1..25}; do
        if curl -fsS --max-time 2 "http://127.0.0.1:$((lab_base + lab_number))/ready" >/dev/null; then lab_ok=true; break; fi
        sleep 1
    done
    $lab_ok || { echo 'Экземпляр не готов. Переключение nginx не выполнялось.'; exit 1; }
done
echo "Группа $lab_color готова с версией $lab_version. Маршрутизация nginx не изменялась."
```

## deploy/scripts/switch-release.sh

Проверка новой группы, переключение nginx и автозапуска.

```
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Нужен sudo'; exit 1; }
lab_color=${1:?Укажите blue или green}
[[ $lab_color == blue || $lab_color == green ]] || exit 2
exec 9>/run/lock/expenses-release.lock
flock 9
if [[ $lab_color == blue ]]; then lab_ports='9101 9102'; lab_other=green; else lab_ports='9201 9202'; lab_other=blue; fi
systemctl start "expenses@$lab_color-1" "expenses@$lab_color-2"
for lab_port in $lab_ports; do
    lab_ok=false
    for lab_attempt in {1..20}; do
        if curl -fsS --max-time 2 "http://127.0.0.1:$lab_port/ready" >/dev/null; then lab_ok=true; break; fi
        sleep 1
    done
    $lab_ok || { echo "Новая версия не готова на порту $lab_port. Трафик не переключён."; exit 1; }
done
lab_old=$(readlink /etc/nginx/expenses-lab/active.conf)
ln -s "$lab_color.conf" /etc/nginx/expenses-lab/active.next
mv -Tf /etc/nginx/expenses-lab/active.next /etc/nginx/expenses-lab/active.conf
if ! nginx -t || ! systemctl reload nginx; then
    ln -sfn "$lab_old" /etc/nginx/expenses-lab/active.conf
    echo 'Переключение отменено; сохранена прежняя конфигурация.'; exit 1
fi
systemctl enable "expenses@$lab_color-1" "expenses@$lab_color-2"
systemctl disable "expenses@$lab_other-1" "expenses@$lab_other-2"
echo "Трафик направлен в $lab_color. Старая группа ещё работает для завершения запросов."
echo "После проверки: sudo systemctl stop expenses@$lab_other-1 expenses@$lab_other-2"
```

## tools/sign_package.sh

Подпись RPM штатной командой SDK.

```
set -euo pipefail
lab_psdk=${LAB_PSDK:-"$HOME/AuroraPlatformSDK/sdks/aurora_psdk"}
lab_sdk=${LAB_SDK:-"$HOME/AuroraOS"}
"$lab_psdk/sdk-chroot" rpmsign-external sign \
    --key "$lab_sdk/package-signing/regular_key.pem" \
    --cert "$lab_sdk/package-signing/regular_cert.pem" "$@"
"$lab_psdk/sdk-chroot" rpmsign-external verify "$@"
```

## client/src/main.cpp

Точка входа нативного приложения и создание зависимостей.

```
#include <auroraapp.h>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QDir>
#include <QDebug>
#include "expensecontroller.h"

int main(int argc, char *argv[]) {
    QScopedPointer<QGuiApplication> app(Aurora::Application::application(argc, argv));
    app->setOrganizationName("com.example");
    app->setApplicationName("expenseslab3");
    try {
        const QString data = Aurora::Application::filesDir().absolutePath();
        QDir().mkpath(data);
        ExpenseController controller(data);
        QScopedPointer<QQuickView> view(Aurora::Application::createView());
        view->rootContext()->setContextProperty("expensesController", &controller);
        view->setSource(Aurora::Application::pathTo("qml/com.example.expenseslab3.qml"));
        if (view->status() == QQuickView::Error) return 1;
        view->show();
        return app->exec();
    } catch (const std::exception &e) {
        qCritical() << "Не удалось открыть локальную базу:" << e.what();
        return 1;
    }
}
```

## client/src/apiclient.h

Интерфейс HTTP-транспорта и структура ответа.

```
#pragma once
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QUrl>
#include <functional>

struct ApiResult {
    int status = 0;
    QJsonDocument json;
    QString error;
    QByteArray etag;
    QByteArray modified;
    QString backendId, appVersion;
    bool ok() const { return status >= 200 && status < 300 && error.isEmpty(); }
};

class ApiClient : public QObject {
    Q_OBJECT
public:
    explicit ApiClient(QObject *parent = nullptr);
    QString baseUrl, token, certificatePath;
    void request(const QByteArray &method, const QString &path, const QJsonObject &body,
                 const QByteArray &key, int version, const QByteArray &etag,
                 std::function<void(ApiResult)> done, int retries = 1);
private:
    QNetworkAccessManager manager;
};
```

## client/src/apiclient.cpp

Асинхронный HTTPS, сертификат, заголовки, JSON и таймаут.

```
#include "apiclient.h"
#include <QBuffer>
#include <QFile>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QTimer>

ApiClient::ApiClient(QObject *parent) : QObject(parent), manager(this) {}

void ApiClient::request(const QByteArray &method, const QString &path, const QJsonObject &body,
                        const QByteArray &key, int version, const QByteArray &etag,
                        std::function<void(ApiResult)> done, int retries) {
    QNetworkRequest req(QUrl(baseUrl + path));
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", "AuroraExpenses/2.0 Qt/5.6");

    req.setRawHeader("Connection", "close");
    if (!token.isEmpty()) req.setRawHeader("Authorization", "Bearer " + token.toUtf8());
    if (!key.isEmpty()) req.setRawHeader("Idempotency-Key", key);
    if (version > 0) req.setRawHeader("If-Match", "\"" + QByteArray::number(version) + "\"");
    if (!etag.isEmpty()) req.setRawHeader("If-None-Match", etag);

    auto ssl = QSslConfiguration::defaultConfiguration();
    auto trusted = ssl.caCertificates();
    trusted.append(QSslCertificate::fromPath(certificatePath));
    ssl.setCaCertificates(trusted);
    req.setSslConfiguration(ssl);
    QByteArray bytes;
    if (!body.isEmpty()) {
        req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
        bytes = QJsonDocument(body).toJson(QJsonDocument::Compact);
    }

    auto *buffer = new QBuffer(&manager);
    buffer->setData(bytes);
    buffer->open(QIODevice::ReadOnly);
    auto *reply = manager.sendCustomRequest(req, method, buffer);
    buffer->setParent(reply);

    auto *timer = new QTimer(reply);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, reply, [reply]() {
        reply->setProperty("timedOut", true);
        reply->abort();
    });
    timer->start(10000);
    connect(reply, &QNetworkReply::finished, this, [this, reply, timer, done, method, path, body, key, version, etag, retries]() {
        timer->stop();
        ApiResult result;
        result.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        result.etag = reply->rawHeader("ETag");
        result.modified = reply->rawHeader("Last-Modified");
        result.backendId = QString::fromUtf8(reply->rawHeader("X-Backend-ID"));
        result.appVersion = QString::fromUtf8(reply->rawHeader("X-App-Version"));
        const auto bytes = reply->readAll();
        QJsonParseError parse;
        result.json = QJsonDocument::fromJson(bytes, &parse);
        if (reply->property("timedOut").toBool()) result.error = "Превышено время ожидания (10 с)";
        else if (result.status == 0) result.error = reply->errorString();
        else if (result.status >= 400) {
            const auto detail = result.json.object().value("detail");
            result.error = detail.isString() ? detail.toString() : "Ошибка HTTP " + QString::number(result.status);
        } else if (result.status != 204 && result.status != 304 && parse.error != QJsonParseError::NoError) {
            result.error = "Сервер вернул некорректный JSON";
        }
        reply->deleteLater();
        if (result.status == 0 && method == "GET" && retries > 0) {

            manager.clearAccessCache();
            QTimer::singleShot(250, this, [this, method, path, body, key, version, etag, done, retries]() {
                request(method, path, body, key, version, etag, done, retries - 1);
            });
            return;
        }
        done(result);
    });
}
```

## client/src/localstore.h

Интерфейс локального хранилища и очереди.

```
#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QString>

class LocalStore {
public:
    explicit LocalStore(const QString &path);
    ~LocalStore();
    QString scope;
    QJsonArray items() const;
    QJsonObject item(const QString &id) const;
    QJsonObject operation(const QString &id = QString()) const;
    int pending() const;
    void enqueue(QJsonObject item, const QString &kind);
    void attempted(const QString &id);
    void acknowledge(const QString &id, const QJsonObject &server);
    void conflict(const QString &id, const QJsonObject &server);
    void resolve(const QString &id, bool keepLocal);
    void snapshot(const QJsonArray &rows, const QByteArray &etag);
    QByteArray etag() const;
private:
    QSqlDatabase db;
    QString connectionName;
    void putItem(const QJsonObject &item);
};
```

## client/src/localstore.cpp

SQLite-кэш, транзакции, offline-операции и разрешение конфликтов.

```
#include "localstore.h"
#include <QJsonDocument>
#include <QSqlError>
#include <QSqlQuery>
#include <QUuid>
#include <QVariant>
#include <stdexcept>

namespace {
QByteArray encode(const QJsonObject &o) { return QJsonDocument(o).toJson(QJsonDocument::Compact); }
QJsonObject decode(const QVariant &v) { return QJsonDocument::fromJson(v.toByteArray()).object(); }
QString uuid() { return QUuid::createUuid().toString().remove('{').remove('}'); }
void check(bool ok, const QSqlQuery &q) {
    if (!ok) throw std::runtime_error(q.lastError().text().toStdString());
}

class Transaction {
    QSqlDatabase &db;
    bool committed = false;
public:
    explicit Transaction(QSqlDatabase &d) : db(d) {
        if (!db.transaction()) throw std::runtime_error(db.lastError().text().toStdString());
    }
    void commit() {
        if (!db.commit()) throw std::runtime_error(db.lastError().text().toStdString());
        committed = true;
    }
    ~Transaction() { if (!committed) db.rollback(); }
};
}

LocalStore::LocalStore(const QString &path) : connectionName("expenses-" + uuid()) {
    db = QSqlDatabase::addDatabase("QSQLITE", connectionName);
    db.setDatabaseName(path);
    if (!db.open()) throw std::runtime_error(db.lastError().text().toStdString());
    QSqlQuery q(db);
    check(q.exec("CREATE TABLE IF NOT EXISTS items(scope TEXT,id TEXT,json BLOB,PRIMARY KEY(scope,id))"), q);
    check(q.exec("CREATE TABLE IF NOT EXISTS outbox(scope TEXT,id TEXT,json BLOB,PRIMARY KEY(scope,id))"), q);
    check(q.exec("CREATE TABLE IF NOT EXISTS validators(scope TEXT PRIMARY KEY,etag BLOB)"), q);
}
LocalStore::~LocalStore() {
    db.close(); db = QSqlDatabase(); QSqlDatabase::removeDatabase(connectionName);
}
QJsonArray LocalStore::items() const {
    QSqlQuery q(db); q.prepare("SELECT json FROM items WHERE scope=? ORDER BY id"); q.addBindValue(scope); check(q.exec(), q);
    QJsonArray result;
    while (q.next()) {
        auto row = decode(q.value(0));
        if (row.value("deleted").toBool()) continue;
        auto op = operation(row.value("id").toString());
        row["pending"] = !op.isEmpty();
        row["conflict"] = op.contains("server");
        result.append(row);
    }
    return result;
}
QJsonObject LocalStore::item(const QString &id) const {
    QSqlQuery q(db); q.prepare("SELECT json FROM items WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    return q.next() ? decode(q.value(0)) : QJsonObject();
}
QJsonObject LocalStore::operation(const QString &id) const {
    QSqlQuery q(db);
    q.prepare(id.isEmpty() ? "SELECT json FROM outbox WHERE scope=? ORDER BY rowid LIMIT 1" : "SELECT json FROM outbox WHERE scope=? AND id=?");
    q.addBindValue(scope); if (!id.isEmpty()) q.addBindValue(id); check(q.exec(), q);
    return q.next() ? decode(q.value(0)) : QJsonObject();
}
int LocalStore::pending() const {
    QSqlQuery q(db); q.prepare("SELECT count(*) FROM outbox WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q); q.next(); return q.value(0).toInt();
}
void LocalStore::putItem(const QJsonObject &row) {
    QSqlQuery q(db); q.prepare("INSERT OR REPLACE INTO items VALUES (?,?,?)");
    q.addBindValue(scope); q.addBindValue(row.value("id").toString()); q.addBindValue(encode(row)); check(q.exec(), q);
}
void LocalStore::enqueue(QJsonObject row, const QString &kind) {
    const auto id = row.value("id").toString();
    auto op = operation(id);
    if (op.value("attempted").toBool() || op.contains("server"))
        throw std::runtime_error("Сначала синхронизируйте ранее отправленную операцию или разрешите конфликт");
    Transaction tx(db);
    QSqlQuery q(db);

    if (kind == "DELETE" && op.value("kind").toString() == "POST") {
        q.prepare("DELETE FROM items WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
        q.prepare("DELETE FROM outbox WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    } else {
        row["deleted"] = kind == "DELETE";
        putItem(row);
        if (op.isEmpty()) {
            op["id"] = id; op["key"] = uuid(); op["kind"] = kind; op["version"] = row.value("version");
        } else if (kind == "DELETE") op["kind"] = kind;
        op["payload"] = row;
        q.prepare("INSERT OR REPLACE INTO outbox VALUES (?,?,?)"); q.addBindValue(scope); q.addBindValue(id); q.addBindValue(encode(op)); check(q.exec(), q);
    }
    tx.commit();
}
void LocalStore::attempted(const QString &id) {
    auto op = operation(id); op["attempted"] = true;
    QSqlQuery q(db); q.prepare("UPDATE outbox SET json=? WHERE scope=? AND id=?");
    q.addBindValue(encode(op)); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
}
void LocalStore::acknowledge(const QString &id, const QJsonObject &server) {
    Transaction tx(db);
    QSqlQuery q(db); q.prepare("DELETE FROM outbox WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    q.prepare("DELETE FROM validators WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    if (server.isEmpty()) {
        q.prepare("DELETE FROM items WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    } else putItem(server);
    tx.commit();
}
void LocalStore::conflict(const QString &id, const QJsonObject &server) {
    auto op = operation(id); op["server"] = server;
    QSqlQuery q(db); q.prepare("UPDATE outbox SET json=? WHERE scope=? AND id=?");
    q.addBindValue(encode(op)); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
}
void LocalStore::resolve(const QString &id, bool keepLocal) {
    auto op = operation(id);
    if (!op.contains("server")) return;
    const auto server = op.value("server").toObject();
    auto local = op.value("payload").toObject();

    Transaction tx(db);
    QSqlQuery q(db);
    q.prepare("DELETE FROM outbox WHERE scope=? AND id=?"); q.addBindValue(scope); q.addBindValue(id); check(q.exec(), q);
    putItem(server);
    if (keepLocal && !(server.value("deleted").toBool() && op.value("kind").toString() == "DELETE")) {
        QString kind = op.value("kind").toString() == "DELETE" ? "DELETE" : "PATCH";
        local["version"] = server.value("version");
        if (server.value("deleted").toBool()) {
            kind = "POST"; local["id"] = uuid(); local["version"] = 0;
        }
        local["deleted"] = kind == "DELETE";
        putItem(local);
        const QJsonObject replacement{{"id", local.value("id")}, {"key", uuid()}, {"kind", kind},
                                      {"version", local.value("version")}, {"payload", local}};
        q.prepare("INSERT INTO outbox VALUES (?,?,?)"); q.addBindValue(scope);
        q.addBindValue(local.value("id").toString()); q.addBindValue(encode(replacement)); check(q.exec(), q);
    }
    q.prepare("DELETE FROM validators WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    tx.commit();
}
void LocalStore::snapshot(const QJsonArray &rows, const QByteArray &value) {

    if (pending()) throw std::runtime_error("Нельзя заменить кэш при непустой очереди");
    Transaction tx(db);
    QSqlQuery q(db); q.prepare("DELETE FROM items WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    for (const auto &v : rows) putItem(v.toObject());
    q.prepare("INSERT OR REPLACE INTO validators VALUES (?,?)"); q.addBindValue(scope); q.addBindValue(value); check(q.exec(), q);
    tx.commit();
}
QByteArray LocalStore::etag() const {
    QSqlQuery q(db); q.prepare("SELECT etag FROM validators WHERE scope=?"); q.addBindValue(scope); check(q.exec(), q);
    return q.next() ? q.value(0).toByteArray() : QByteArray();
}
```

## client/src/expensecontroller.h

Свойства и действия, доступные интерфейсу QML.

```
#pragma once
#include "apiclient.h"
#include "localstore.h"
#include "pushservice.h"
#include <QSettings>
#include <QTimer>
#include <QVariantList>

class ExpenseController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList expenses READ expenses NOTIFY changed)
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY changed)
    Q_PROPERTY(bool offline READ offline WRITE setOffline NOTIFY changed)
    Q_PROPERTY(QString serverUrl READ serverUrl NOTIFY changed)
    Q_PROPERTY(QString username READ username NOTIFY changed)
    Q_PROPERTY(QString certificatePath READ certificatePath NOTIFY changed)
    Q_PROPERTY(QVariantMap conflictInfo READ conflictInfo NOTIFY changed)
    Q_PROPERTY(QString pushStatus READ pushStatus NOTIFY changed)
    Q_PROPERTY(QString lastPush READ lastPush NOTIFY changed)
    Q_PROPERTY(int pushCount READ pushCount NOTIFY changed)
    Q_PROPERTY(QString backend READ backend NOTIFY changed)
public:
    explicit ExpenseController(const QString &dataDir, QObject *parent = nullptr);
    ~ExpenseController() override;
    QVariantList expenses() const { return store.items().toVariantList(); }
    int pendingCount() const { return store.pending(); }
    QString status() const { return message; }
    bool busy() const { return running; }
    bool authenticated() const { return !api.token.isEmpty(); }
    bool offline() const { return offlineMode; }
    QString serverUrl() const { return api.baseUrl; }
    QString username() const { return account; }
    QString certificatePath() const { return api.certificatePath; }
    QVariantMap conflictInfo() const;
    QString pushStatus() const { return pushMessage; }
    QString lastPush() const { return lastEvent; }
    int pushCount() const { return eventCount; }
    QString backend() const { return lastBackend; }
    Q_INVOKABLE void login(QString url, QString user, QString password, QString cert);
    Q_INVOKABLE void logout();
    Q_INVOKABLE void sync();
    Q_INVOKABLE bool save(QString id, QString date, QString category, QString amount, QString comment);
    Q_INVOKABLE void remove(QString id);
    Q_INVOKABLE void resolve(bool keepLocal);
    void setOffline(bool value);
signals:
    void changed();

    void expenseChanged(QVariantMap event);
private:
    ApiClient api;
    PushService push;
    LocalStore store;
    QSettings settings;
    QTimer retry;
    QString account, message;
    bool running = false, offlineMode = false;
    bool resyncRequested = false;
    int eventCount = 0;
    QString pushMessage, lastEvent, lastBackend;
    void next();
    void failed(const ApiResult &result);
    void finish(QString text);
    void configureScope();
    void configurePush();
};
```

## client/src/expensecontroller.cpp

Бизнес-правила, сессия и последовательность синхронизации.

```
#include "expensecontroller.h"
#include <QDate>
#include <QJsonArray>
#include <QJsonObject>
#include <QRegularExpression>
#include <QUrl>
#include <QUuid>

ExpenseController::ExpenseController(const QString &dataDir, QObject *parent)
    : QObject(parent), api(this), push(this), store(dataDir + "/expenses.sqlite") {
    api.baseUrl = settings.value("server", "https://192.168.0.118:9443").toString();
    api.certificatePath = settings.value("certificate", "/usr/share/com.example.expenseslab3/certificates/server.crt").toString();
    account = settings.value("username", "demo").toString();
    api.token = settings.value("token").toString();
    offlineMode = settings.value("offline", false).toBool();
    connect(&push, &PushService::statusChanged, this, [this](QString value) {
        pushMessage = value; emit changed();
    });
    connect(&push, &PushService::connected, this, [this]() {

        if (running) resyncRequested = true; else sync();
    });
    connect(&push, &PushService::eventReceived, this, [this](QJsonObject event) {
        if (event.value("type") == "expense.changed") {
            ++eventCount;
            lastEvent = event.value("action").toString() + " · " + event.value("instance").toString();
            emit expenseChanged(event.toVariantMap());
        }
        emit changed();
        if (running) resyncRequested = true; else sync();
    });
    configureScope();
    message = "Показаны сохранённые данные. Нажмите «Синхронизировать».";

    retry.setInterval(30000);
    connect(&retry, &QTimer::timeout, this, &ExpenseController::sync);
    retry.start();
    QTimer::singleShot(0, this, [this]() { configurePush(); });
}

ExpenseController::~ExpenseController() {

    push.disconnect(this);
    push.stop();
}

void ExpenseController::configurePush() {
    if (offlineMode || !authenticated()) push.stop();
    else push.start(api.baseUrl, api.token, api.certificatePath);
}

void ExpenseController::configureScope() {
    store.scope = api.baseUrl + "\n" + account;
}

void ExpenseController::login(QString url, QString user, QString password, QString cert) {
    if (running || offlineMode) return;
    url = url.trimmed();
    while (url.endsWith('/')) url.chop(1);
    const QUrl parsed(url);
    if (!parsed.isValid() || parsed.scheme() != "https" || parsed.host().isEmpty()
        || !parsed.userInfo().isEmpty() || !parsed.query().isEmpty() || !parsed.fragment().isEmpty()
        || (!parsed.path().isEmpty() && parsed.path() != "/")) {
        finish("Адрес должен иметь вид https://<IP-ПК>:9443"); return;
    }
    if (user.trimmed().isEmpty() || password.isEmpty()) { finish("Введите логин и пароль"); return; }
    push.stop();
    running = true; message = "Вход…"; emit changed();
    const auto oldUrl = api.baseUrl, oldCert = api.certificatePath, oldToken = api.token;
    api.baseUrl = url; api.certificatePath = cert.trimmed(); api.token.clear();
    api.request("POST", "/api/v1/auth/login", {{"username", user.trimmed()}, {"password", password}}, {}, 0, {},
        [this, user, oldUrl, oldCert, oldToken](ApiResult result) {
        if (!result.ok() || !result.json.object().value("access_token").isString()) {
            api.baseUrl = oldUrl; api.certificatePath = oldCert; api.token = oldToken;
            finish("Не удалось войти: " + result.error); configurePush(); return;
        }
        account = user.trimmed(); api.token = result.json.object().value("access_token").toString();
        settings.setValue("server", api.baseUrl); settings.setValue("certificate", api.certificatePath);
        settings.setValue("username", account); settings.setValue("token", api.token); settings.sync();
        configureScope(); configurePush(); running = false; emit changed(); sync();
    });
}

void ExpenseController::logout() {
    if (running) return;
    push.stop();
    api.token.clear(); settings.remove("token"); settings.sync();

    finish("Вы вышли. Локальные данные сохранены для следующего входа.");
}

void ExpenseController::setOffline(bool value) {
    if (running) return;
    offlineMode = value; settings.setValue("offline", value); settings.sync(); emit changed();
    configurePush();
    if (value) finish("Offline: изменения сохраняются только на телефоне"); else sync();
}

void ExpenseController::finish(QString text) {
    running = false; message = text; emit changed();
    if (resyncRequested) {
        resyncRequested = false;
        QTimer::singleShot(0, this, &ExpenseController::sync);
    }
}
void ExpenseController::failed(const ApiResult &result) {
    if (result.status == 401) {
        push.stop();
    api.token.clear(); settings.remove("token"); settings.sync();
        finish("Сессия истекла. Войдите заново; очередь изменений сохранена.");
    } else finish(result.error + ". Локальные данные и очередь сохранены.");
}

void ExpenseController::sync() {
    if (running || offlineMode || !authenticated()) return;
    configurePush();
    running = true; message = "Синхронизация…"; emit changed();
    next();
}
void ExpenseController::next() {
    try {
        const auto op = store.operation();
        if (op.contains("server")) { finish("Конфликт: выберите локальную или серверную версию"); return; }
        if (op.isEmpty()) {
            api.request("GET", "/api/v1/expenses?include_deleted=true", {}, {}, 0, store.etag(), [this](ApiResult r) {
                try {
                    lastBackend = r.backendId + " · v" + r.appVersion;
                    if (r.status == 304) { finish("Данные актуальны (HTTP 304)"); return; }
                    if (!r.ok()) { failed(r); return; }
                    if (!r.json.isArray()) { finish("Ошибка: вместо списка получен другой JSON"); return; }
                    store.snapshot(r.json.array(), r.etag);
                    finish("Синхронизация завершена");
                } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
            });
            return;
        }
        const auto id = op.value("id").toString();
        const auto kind = op.value("kind").toString();
        const auto payload = op.value("payload").toObject();
        QJsonObject body;
        if (kind != "DELETE") {
            for (const auto &key : {"date", "category", "amount_minor", "comment"}) body[key] = payload.value(key);
            if (kind == "POST") body["id"] = id;
        }
        store.attempted(id);
        api.request(kind.toUtf8(), "/api/v1/expenses" + (kind == "POST" ? QString() : "/" + id), body,
                    op.value("key").toString().toUtf8(), op.value("version").toInt(), {},
                    [this, id, kind](ApiResult r) {
            try {
                if (r.status == 409) {
                    const auto server = r.json.object().value("detail").toObject().value("server").toObject();
                    if (!server.isEmpty()) store.conflict(id, server);
                    finish("Конфликт изменений. Выберите версию в блоке синхронизации."); return;
                }
                if (!r.ok()) { failed(r); return; }
                if (kind != "DELETE" && (!r.json.isObject() || r.json.object().value("id").toString() != id)) {
                    finish("Неверный ответ сервера: операция сохранена для повтора"); return;
                }
                store.acknowledge(id, kind == "DELETE" ? QJsonObject() : r.json.object());
                emit changed(); next();
            } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
        });
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
}

bool ExpenseController::save(QString id, QString date, QString category, QString amount, QString comment) {
    if (running || !authenticated()) return false;
    const auto parsedDate = QDate::fromString(date, Qt::ISODate);
    const auto match = QRegularExpression("^([0-9]{1,10})(?:[.,]([0-9]{1,2}))?$").match(amount.trimmed());
    if (!parsedDate.isValid() || parsedDate.toString(Qt::ISODate) != date || !match.hasMatch()
        || category.trimmed().isEmpty() || category.trimmed().size() > 80 || comment.size() > 2000) {
        finish("Проверьте дату YYYY-MM-DD, категорию, сумму и длину комментария"); return false;
    }
    const qint64 minor = match.captured(1).toLongLong() * 100 + match.captured(2).leftJustified(2, '0').toInt();
    if (minor <= 0 || minor > 100000000000LL) { finish("Сумма должна быть больше 0 и не больше 1 000 000 000 рублей"); return false; }
    try {
        auto row = id.isEmpty() ? QJsonObject() : store.item(id);
        const bool created = id.isEmpty();
        if (created) { id = QUuid::createUuid().toString().remove('{').remove('}'); row["version"] = 0; }
        else if (row.isEmpty() || row.value("deleted").toBool()) { finish("Расход больше не существует"); return false; }
        row["id"] = id; row["date"] = date; row["category"] = category.trimmed();
        row["amount_minor"] = static_cast<double>(minor); row["comment"] = comment.trimmed();
        store.enqueue(row, created ? "POST" : "PATCH");
        finish("Изменения сохранены на телефоне"); sync(); return true;
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); return false; }
}
void ExpenseController::remove(QString id) {
    if (running || !authenticated()) return;
    try {
        auto row = store.item(id);
        if (row.isEmpty()) return;
        store.enqueue(row, "DELETE"); finish("Удаление сохранено на телефоне"); sync();
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
}
QVariantMap ExpenseController::conflictInfo() const {
    const auto op = store.operation();
    return op.contains("server") ? op.toVariantMap() : QVariantMap();
}
void ExpenseController::resolve(bool keepLocal) {
    if (running) return;
    try {
        const auto op = store.operation();
        if (!op.contains("server")) return;
        store.resolve(op.value("id").toString(), keepLocal);
        finish("Конфликт разрешён"); sync();
    } catch (const std::exception &e) { finish(QString::fromUtf8(e.what())); }
}
```

## client/qml/com.example.expenseslab3.qml

Корневое окно приложения и обложка.

```
import QtQuick 2.0
import Sailfish.Silica 1.0
import "services"

ApplicationWindow {
    id: app
    SystemNotification { controller: expensesController }
    initialPage: Component { MainPage {} }
    cover: Component {
        CoverBackground {
            Label { anchors.centerIn: parent; text: "Расходы ЛР3\n" + expensesController.pendingCount + " в очереди"; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
```

## client/qml/MainPage.qml

Вход, настройки, список, статусы и выбор версии при конфликте.

```
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All
    property var controller: expensesController
    SilicaListView {
        id: list
        anchors.fill: parent
        model: controller.expenses
        PullDownMenu {
            MenuItem { text: "Новый расход"; enabled: !controller.busy && controller.authenticated; onClicked: pageStack.push(Qt.resolvedUrl("ExpenseDialog.qml")) }
            MenuItem { text: "Синхронизировать"; enabled: !controller.busy && controller.authenticated && !controller.offline; onClicked: controller.sync() }
        }
        header: Column {
            width: list.width
            PageHeader { title: "Расходы ЛР3" }
            SectionHeader { text: "Сервер и вход" }
            TextField { id: server; width: parent.width; label: "HTTPS-адрес ПК"; text: controller.serverUrl; enabled: !controller.busy; inputMethodHints: Qt.ImhUrlCharactersOnly }
            TextField { id: user; width: parent.width; label: "Пользователь"; text: controller.username; enabled: !controller.busy }
            PasswordField { id: password; width: parent.width; label: "Пароль"; enabled: !controller.busy }
            TextField { id: cert; width: parent.width; label: "Путь к доверенному сертификату"; text: controller.certificatePath; enabled: !controller.busy }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Войти"; enabled: !controller.busy && !controller.offline
                onClicked: { controller.login(server.text, user.text, password.text, cert.text); password.text = "" }
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Выйти"; enabled: !controller.busy && controller.authenticated
                onClicked: controller.logout()
            }
            TextSwitch { text: "Работать offline"; description: "Не отправлять запросы, сохранять изменения на телефоне"; checked: controller.offline; enabled: !controller.busy; onClicked: controller.offline = checked }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: controller.status; wrapMode: Text.Wrap; color: Theme.highlightColor
            }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: controller.pushStatus + "\nREST: " + controller.backend
                wrapMode: Text.Wrap; font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                visible: controller.pushCount > 0
                text: "Push-событий: " + controller.pushCount + " · " + controller.lastPush
                wrapMode: Text.Wrap; color: Theme.highlightColor
            }
            BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; size: BusyIndicatorSize.Medium; running: controller.busy; visible: running }
            Label {
                x: Theme.horizontalPageMargin; width: parent.width - 2*x
                text: "Изменений в очереди: " + controller.pendingCount; wrapMode: Text.Wrap
            }
            Column {
                width: parent.width
                visible: !!controller.conflictInfo.server
                SectionHeader { text: "Конфликт изменений" }
                Label {
                    x: Theme.horizontalPageMargin; width: parent.width - 2*x; wrapMode: Text.Wrap
                    text: {
                        var info = controller.conflictInfo
                        if (!info.server) return ""
                        var s = info.server, l = info.payload
                        return "Локально: " + l.date + " · " + l.category + " · " + (l.amount_minor/100).toFixed(2) + " ₽ · " + l.comment + (info.kind === "DELETE" ? " (удаление)" : "") +
                                "\nНа сервере: " + s.date + " · " + s.category + " · " + (s.amount_minor/100).toFixed(2) + " ₽ · " + s.comment + (s.deleted ? " (удалено)" : "")
                    }
                }
                Button { text: "Принять серверную"; anchors.horizontalCenter: parent.horizontalCenter; enabled: !controller.busy; onClicked: controller.resolve(false) }
                Button { text: "Сохранить локальную"; anchors.horizontalCenter: parent.horizontalCenter; enabled: !controller.busy; onClicked: controller.resolve(true) }
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter; text: "Новый расход"
                enabled: !controller.busy && controller.authenticated
                onClicked: pageStack.push(Qt.resolvedUrl("ExpenseDialog.qml"))
            }
            SectionHeader { text: "Сохранённые расходы" }
            Label { x: Theme.horizontalPageMargin; text: "Пока нет расходов"; visible: list.count === 0 }
        }
        delegate: ListItem {
            id: entry
            property var row: modelData
            contentHeight: details.height + 2*Theme.paddingMedium
            enabled: !controller.busy && controller.authenticated
            onClicked: pageStack.push(Qt.resolvedUrl("ExpenseDialog.qml"), {record: row})
            menu: ContextMenu {
                MenuItem { text: "Редактировать"; onClicked: pageStack.push(Qt.resolvedUrl("ExpenseDialog.qml"), {record: entry.row}) }
                MenuItem { text: "Удалить"; onClicked: entry.remorseAction("Удаление", function () { controller.remove(entry.row.id) }) }
            }
            Column {
                id: details; x: Theme.horizontalPageMargin; width: parent.width - 2*x; y: Theme.paddingMedium
                Label { width: parent.width; text: row.date + " · " + row.category; wrapMode: Text.Wrap; color: Theme.highlightColor }
                Label { width: parent.width; text: (row.amount_minor/100).toFixed(2) + " ₽" + (row.conflict ? " · конфликт" : row.pending ? " · не отправлено" : ""); wrapMode: Text.Wrap }
                Label { width: parent.width; text: row.comment; visible: text.length > 0; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.Wrap }
            }
        }
        VerticalScrollDecorator {}
    }
}
```

## client/qml/ExpenseDialog.qml

Форма создания и редактирования расхода.

```
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: dialog
    property var record: ({})
    SilicaFlickable {
        anchors.fill: parent; contentHeight: fields.height
        Column {
            id: fields; width: parent.width
            PageHeader { title: record.id ? "Редактирование" : "Новый расход" }
            TextField { id: date; width: parent.width; label: "Дата YYYY-MM-DD"; text: record.date || Qt.formatDate(new Date(), "yyyy-MM-dd") }
            TextField { id: category; width: parent.width; label: "Категория"; text: record.category || "" }
            TextField { id: amount; width: parent.width; label: "Сумма, рубли"; inputMethodHints: Qt.ImhFormattedNumbersOnly; text: record.amount_minor ? (record.amount_minor/100).toFixed(2) : "" }
            TextArea { id: comment; width: parent.width; label: "Комментарий"; text: record.comment || "" }
            Button {
                text: "Сохранить"; anchors.horizontalCenter: parent.horizontalCenter
                enabled: !expensesController.busy && expensesController.authenticated
                onClicked: {

                    if (expensesController.save(record.id || "", date.text, category.text, amount.text, comment.text)) pageStack.pop()
                    else error.text = expensesController.status
                }
            }
            Label { id: error; x: Theme.horizontalPageMargin; width: parent.width - 2*x; wrapMode: Text.Wrap; color: Theme.highlightColor }
        }
        VerticalScrollDecorator {}
    }
}
```

## client/com.example.expenseslab3.pro

Модули Qt и установка публичного сертификата.

```
TARGET = com.example.expenseslab3
CONFIG += auroraapp c++11
QT += network sql
RESOURCES += services.qrc
SOURCES += src/main.cpp src/apiclient.cpp src/localstore.cpp src/expensecontroller.cpp
SOURCES += src/pushservice.cpp
HEADERS += src/apiclient.h src/localstore.h src/expensecontroller.h
HEADERS += src/pushservice.h
AURORAAPP_ICONS = 86
certificates.files = ../certificates/server.crt
certificates.path = /usr/share/$${TARGET}/certificates
INSTALLS += certificates
DISTFILES += rpm/com.example.expenseslab3.spec
```

## client/com.example.expenseslab3.desktop

Значок запуска и разрешение Internet.

```
[Desktop Entry]
Type=Application
X-Nemo-Application-Type=silica-qt5
Icon=com.example.expenseslab3
Exec=/usr/bin/com.example.expenseslab3
Name=Расходы ЛР3

[X-Application]
Permissions=Internet
OrganizationName=com.example
ApplicationName=expenseslab3
ExecDBus=/usr/bin/com.example.expenseslab3
```

## client/rpm/com.example.expenseslab3.spec

Сборка и упаковка приложения и тестов в RPM.

```
Name: com.example.expenseslab3
Summary: Scalable expenses — laboratory 3
Version: 2.0.0
Release: 10
License: BSD-3-Clause
URL: https://developer.auroraos.ru
Source0: %{name}-%{version}.tar.bz2
Requires: sailfishsilica-qt5 >= 0.10.9
Requires: qt5-plugin-sqldriver-sqlite
Requires: qt5-qtwebsockets
Requires: qt5-qtdeclarative-import-websockets
Requires: nemo-qml-plugin-notifications-qt5
BuildRequires: pkgconfig(auroraapp)
BuildRequires: pkgconfig(Qt5Core)
BuildRequires: pkgconfig(Qt5Qml)
BuildRequires: pkgconfig(Qt5Quick)
BuildRequires: pkgconfig(Qt5Network)
BuildRequires: pkgconfig(Qt5Sql)

%description
REST HTTPS client with SQLite cache and persistent offline synchronization.

%prep
%autosetup

%build
%qmake5
make %{?_smp_mflags}
(cd tests && qmake -qt=5 tests.pro && make %{?_smp_mflags})

%install
%qmake5_install
install -Dm755 tests/expenses-tests %{buildroot}%{_bindir}/com.example.expenseslab3-tests

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_bindir}/com.example.expenseslab3-tests
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Sun Oct 25 2026 Student <student@example.com> - 1.0.0-1
- Initial laboratory implementation.
```

## 2.2. Проверка

26 октября 2026 года на телефоне прошла сквозная проверка системных уведомлений: внешние POST/PATCH/DELETE → WSS → штатный диспетчер ОС. Получен ненулевой ID, изменения заменяют одну запись; повторы и heartbeat отфильтрованы. Повторно прошли прежние HTTPS/SQLite/WSS-сценарии. Журнал: docs/notification-validation.txt. Пользователь также подтвердил работу системных уведомлений на телефоне при изменении расхода через браузер. Отдельная проверка обоих способов отображения не уточнялась. Показ баннера зависит от настроек ОС; получение после полного закрытия приложения не реализовано.

После разделения два самостоятельных подписанных RPM одновременно установлены на телефон. Оба интерфейса запускаются; пути ресурсов и локальных баз различаются. Повторные нативные тесты SQLite, HTTPS, offline CRUD, восстановления очереди, конфликтов и ETag прошли, для ЛР3 также прошли WSS и автоматическое обновление REST по push. Результат: docs/client-separation-validation.txt. Текущий проверенный адрес сервера — https://192.168.0.104:9443; его следует указать в поле адреса приложения.

Реальный сценарий отказа и blue-green: 334 успешных HTTPS-запросов, ошибок: 0. Проверены остановка backend, переподключение WSS, push на оставшемся backend, переход на green, новая функция summary и откат на blue. Полный журнал — docs/cluster-validation.json.

Пять интеграционных тестов подтверждают балансировку, общий JWT, идемпотентность и блокировки при параллельных мутациях, push между backend и изоляцию пользователей. Нативные результаты и сценарий демонстрации приведены в docs/VALIDATION.md. Снимки экрана исключены согласно политике устройства.

На реальном телефоне подтверждены WSS-авторизация, получение внешних CRUD-событий, автоматическое обновление списка, offline-очередь, восстановление контроллера и ETag.

Совместный нативный монитор подтвердил переподключение телефона при отказе и blue-green, получение push на новых соединениях и успешные HTTP-запросы после возврата blue.

Фактические счётчики телефона: requests= 161 failures= 0 connections= 4 events= 3

Команды установки, запуска, сборки, подписи, переключения и отката приведены в README.md. После испытаний активна blue-группа.
