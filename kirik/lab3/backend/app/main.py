# API и сетевые обработчики: маршруты, формат обмена и ошибки. Путь данных: JSON → схема →
# пользователь/права → транзакция → ответ. Depends передаёт проверенные зависимости обработчику; UI
# телефона не выполняет серверный SQL.
"""REST API v1 для нескольких процессов: PostgreSQL, JWT и WebSocket push."""
# asyncio управляет задачами и очередями; await отдаёт управление циклу событий, пока операция не
# готова.
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

# JWT создаёт и проверяет подписанные токены. Подпись защищает целостность, но не шифрует содержимое.
import jwt
# FastAPI задаёт приложение, маршруты, HTTP-ответы и Depends. Импорт ещё не запускает сервер.
from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response, WebSocket, WebSocketDisconnect
# FastAPI задаёт приложение, маршруты, HTTP-ответы и Depends. Импорт ещё не запускает сервер.
from fastapi.exceptions import RequestValidationError
# FastAPI задаёт приложение, маршруты, HTTP-ответы и Depends. Импорт ещё не запускает сервер.
from fastapi.responses import FileResponse, JSONResponse
# FastAPI задаёт приложение, маршруты, HTTP-ответы и Depends. Импорт ещё не запускает сервер.
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
# FastAPI задаёт приложение, маршруты, HTTP-ответы и Depends. Импорт ещё не запускает сервер.
from fastapi.openapi.utils import get_openapi

from .push import PushHub
from .schemas import TaskCreate, TaskPatch, Login
from .storage import Database, password_hash

# __file__ — путь модуля; resolve делает его абсолютным, parents[1] берёт каталог backend. Ресурсы
# находятся независимо от текущего cwd.
ROOT = Path(__file__).resolve().parents[1]
# FastAPI извлекает Bearer-заголовок, но auto_error=False позволяет нашему current_user единообразно
# вернуть 401 при отсутствии токена.
bearer = HTTPBearer(auto_error=False)


# Возвращает время UTC в ISO-формате с микросекундами. Единый часовой пояс позволяет сравнивать
# обновления независимо от настроек компьютера.
def now():
    return datetime.now(timezone.utc).isoformat(timespec='microseconds')


# Преобразует строку задачи в публичный JSON: скрывает owner, приводит deleted к bool. version и
# updated_at сохраняются для синхронизации.
def task(row):
    result = dict(row)
    # Удаляем служебное поле владельца из ответа. None делает удаление безопасным, если ключ отсутствует.
    result.pop('owner', None)
    # SQLite/PostgreSQL хранят флаг числом, а JSON-контракт выдаёт логическое true/false.
    result['deleted'] = bool(result['deleted'])
    return result


# Фабрика создаёт БД и FastAPI, регистрирует обработчики/маршруты. Параметры позволяют тесту передать
# изолированную БД и ключ. Возвращённый app передаётся Uvicorn, который обслуживает HTTP.
def create_app(dsn=None, secret=None, release=None, instance=None):
    # Если тест не передал DSN, читаем обязательную переменную окружения. Отсутствующая настройка должна
    # обнаружиться при запуске.
    dsn = dsn or os.environ['DATABASE_URL']
    # Общий секрет JWT должен совпадать у всех backend: токен, выданный одним процессом, проверяется
    # другим.
    secret = secret or os.environ['JWT_SECRET']
    if len(secret) < 32:
        raise ValueError('JWT_SECRET должен иметь не менее 32 символов')
    release = release or json.loads((Path(__file__).parent / 'release.json').read_text())
    # Уникальное имя процесса/экземпляра нужно диагностике; оно не является идентификатором пользователя.
    instance = instance or os.getenv('INSTANCE_ID', 'dev-1')
    # DSN задаёт адрес/аккаунт PostgreSQL. Все экземпляры должны видеть одну БД, иначе балансировка
    # показывала бы разные данные.
    db = Database(dsn)
    # Готовим общую схему до обслуживания запросов. Одновременные процессы используют блокировку и IF NOT
    # EXISTS, не создавая разные БД.
    db.initialize()
    # Этот процесс слушает тот же PostgreSQL-канал, что остальные backend. Без моста изменения другого
    # процесса не дошли бы до его WSS-клиентов.
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

    # Преобразует ошибки Pydantic в HTTP 400 с перечнем неверных полей. Обработчик возвращает клиенту
    # объяснение вместо внутренней трассировки.
    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        return JSONResponse(status_code=400, content={'detail': 'Некорректные поля запроса',
            'fields': [{'field': '.'.join(map(str, e['loc'])), 'message': e['msg']} for e in exc.errors()]})

    # Непредусмотренная ошибка записывается в серверный журнал, клиент получает общее сообщение HTTP 500
    # без внутренних деталей.
    @app.exception_handler(Exception)
    async def unexpected_error(request, exc):
        logging.exception('Ошибка обработки API', exc_info=exc)
        return JSONResponse(status_code=500, content={'detail': 'Внутренняя ошибка сервера'})

    # Middleware оборачивает каждый HTTP-запрос: проверяет Content-Type мутаций, вызывает маршрут и
    # дополняет заголовки ответа.
    @app.middleware('http')
    async def headers(request, call_next):
        if request.method in ('POST', 'PATCH') and request.url.path.startswith('/api/'):
            if request.headers.get('content-type', '').split(';')[0].strip() != 'application/json':
                return JSONResponse(status_code=415, content={'detail': 'Требуется application/json'})
        response = await call_next(request)
        # Помечаем HTTP-ответ именем обслужившего процесса. UI показывает этот заголовок как последний
        # REST-backend.
        response.headers['X-Backend-ID'] = instance
        # Версия из снимка релиза подтверждает, какой код реально обработал запрос после blue-green.
        response.headers['X-App-Version'] = release['version']
        # Запрещаем браузеру угадывать другой MIME-тип ответа вместо указанного сервером.
        response.headers['X-Content-Type-Options'] = 'nosniff'
        if 'cache-control' not in response.headers:
            # По умолчанию не сохраняем чувствительные ответы. Маршрут чтения с ETag задаёт свою более точную
            # политику.
            response.headers['Cache-Control'] = 'no-store'
        return response

    # Depends передаёт Bearer JWT. Проверяем подпись и exp, ищем пользователя по sub. Без достоверной
    # сессии возвращаем 401: простого чтения текста токена недостаточно.
    def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        try:
            if credentials is None:
                raise ValueError()
            # Проверяем алгоритм, подпись и обязательные поля. Просто декодированный JSON не является
            # доказательством входа.
            payload = jwt.decode(credentials.credentials, secret, algorithms=['HS256'],
                                 options={'require': ['exp', 'sub']})
            # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
            # откатывает; ресурс освобождается при выходе.
            with db.connect() as conn:
                # SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; fetchone берёт
                # одну строку, fetchall — все найденные.
                row = conn.execute('SELECT * FROM users WHERE username=%s', (payload['sub'],)).fetchone()
            if row is None:
                raise ValueError()
            return dict(row)
        except (ValueError, jwt.PyJWTError):
            raise HTTPException(401, 'Войдите заново: токен отсутствует или истёк',
                                headers={'WWW-Authenticate': 'Bearer'})

    # Проверяет роль аутентифицированного пользователя. 403 означает, что вход выполнен, но роль разрешает
    # только чтение; 401 означает отсутствие действительного входа.
    def writer(user=Depends(current_user)):
        if user['role'] != 'writer':
            raise HTTPException(403, 'Этому пользователю доступно только чтение')
        return user

    # Лёгкая проверка, что процесс отвечает. Она не выполняет пользовательскую операцию и не заменяет
    # проверку готовности БД.
    @app.get('/health')
    def health():
        return {'status': 'ok'}

    # Отдаёт HTML браузерного интерфейса из static. Страница и API имеют общий origin: браузер обращается
    # по относительным адресам.
    @app.get('/', include_in_schema=False)
    def browser():
        return FileResponse(ROOT / 'static' / 'index.html')

    # Отдаёт JavaScript с корректным MIME-типом. Разметка и поведение страницы хранятся отдельно.
    @app.get('/browser.js', include_in_schema=False)
    def script():
        return FileResponse(ROOT / 'static' / 'browser.js', media_type='application/javascript')

    # Проверяет пароль через хеш и выдаёт JWT: sub обозначает пользователя, exp ограничивает срок
    # действия. Последующие запросы передают токен вместо пароля.
    @app.post('/api/v1/auth/login')
    def login(body: Login):
        # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
        # откатывает; ресурс освобождается при выходе.
        with db.connect() as conn:
            # SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; fetchone берёт
            # одну строку, fetchall — все найденные.
            row = conn.execute('SELECT * FROM users WHERE username=%s', (body.username,)).fetchone()
        # Соль участвует в хеше пароля и не является паролем. Случайность различает хеши одинаковых паролей.
        salt = row['salt'] if row else '00' * 16
        checked = password_hash(body.password, salt)
        if not row or not hmac.compare_digest(checked, row['password_hash']):
            raise HTTPException(401, 'Неправильное имя пользователя или пароль',
                                headers={'WWW-Authenticate': 'Bearer'})
        # Подписываем sub и exp, чтобы клиент использовал ограниченную сессию вместо повторной передачи
        # пароля.
        token = jwt.encode({'sub': row['username'], 'exp': datetime.now(timezone.utc) + timedelta(hours=8)},
                           secret, algorithm='HS256')
        return {'access_token': token, 'token_type': 'bearer', 'username': row['username']}

    # Строит ETag и Last-Modified. При актуальном клиентском валидаторе отвечает 304 без тела, иначе
    # возвращает данные. private/Vary отделяют кэш разных пользователей.
    def cached(request, records, single=False):
        # Валидатор зависит от содержимого, в том числе от tombstones и владельца URL-кэша.
        # Стабильный порядок ключей даёт одинаковый хеш одинакового содержимого. ensure_ascii=False сохраняет
        # читаемый Unicode.
        encoded = json.dumps(records, ensure_ascii=False, sort_keys=True)
        # ETag — непрозрачный валидатор версии. Кавычки входят в HTTP-формат и должны передаваться обратно
        # клиентом.
        etag = '"' + hashlib.sha256(encoded.encode()).hexdigest() + '"'
        if single:
            # ETag — непрозрачный валидатор версии. Кавычки входят в HTTP-формат и должны передаваться обратно
            # клиентом.
            etag = '"' + str(records[0]['version']) + '"'
        latest = max((r['updated_at'] for r in records), default='1970-01-01T00:00:00+00:00')
        modified = datetime.fromisoformat(latest).replace(microsecond=0)
        hdr = {'ETag': etag, 'Last-Modified': format_datetime(modified, usegmt=True),
               'Cache-Control': 'private, no-cache', 'Vary': 'Authorization'}
        # Читаем валидатор клиента. Отсутствие заголовка отличается от неверного/устаревшего значения.
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

    # Читает записи только текущего владельца. include_deleted нужен синхронизации: tombstone сообщает
    # клиенту об удалении, пока тот был offline.
    @app.get('/api/v1/tasks', responses={304: {'description': 'Кэш актуален, тело отсутствует'}})
    def listing(request: Request, include_deleted: bool = False, user=Depends(current_user)):
        # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
        # откатывает; ресурс освобождается при выходе.
        with db.connect() as conn:
            # SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; fetchone берёт
            # одну строку, fetchall — все найденные.
            rows = conn.execute('SELECT * FROM tasks WHERE owner=%s ORDER BY due_date DESC,id', (user['username'],)).fetchall()
        records = [task(r) for r in rows if include_deleted or not r['deleted']]
        return cached(request, records)

    # Находит запись и проверяет владельца. Чужая и отсутствующая запись одинаково дают 404, чтобы не
    # раскрывать чужие идентификаторы.
    def owned(conn, record_id, user):
        # SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; fetchone берёт
        # одну строку, fetchall — все найденные.
        row = conn.execute('SELECT * FROM tasks WHERE id=%s FOR UPDATE', (str(record_id),)).fetchone()
        # Проверка владельца выполняется сервером. Скрыть строку только в UI недостаточно для разграничения
        # доступа.
        if row is None or row['owner'] != user['username']:
            raise HTTPException(404, 'Задача не найден')
        return row

    # Читает одну запись владельца. Удалённая запись недоступна обычному чтению; для существующей
    # применяется кэширование по версии.
    @app.get('/api/v1/tasks/{record_id}', responses={304: {'description': 'Кэш актуален, тело отсутствует'}})
    def get_one(record_id: UUID, request: Request, user=Depends(current_user)):
        # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
        # откатывает; ресурс освобождается при выходе.
        with db.connect() as conn:
            row = owned(conn, record_id, user)
        # Tombstone сохраняет факт удаления для синхронизации; обычное чтение/правка удалённой записи
        # ограничены.
        if row['deleted']:
            raise HTTPException(404, 'Задача удалён')
        return cached(request, [task(row)], single=True)

    # Ищет квитанцию по owner + Idempotency-Key. Повтор прежнего запроса получает прежний ответ; тот же
    # ключ с другим fingerprint вызывает 409. Повтор после обрыва не создаёт дубль.
    def replay(conn, key, fingerprint, user):
        if not key or len(key) > 128:
            raise HTTPException(400, 'Укажите Idempotency-Key длиной до 128 символов')
        # Один ключ сериализуется во всех backend. Повтор после потери ответа
        # увидит квитанцию, даже если первый запрос ещё выполняется.
        # Транзакционная блокировка сериализует одновременную инициализацию схемы. Освобождается при
        # завершении транзакции.
        conn.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', (user['username'] + ':' + key,))
        # SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; fetchone берёт
        # одну строку, fetchall — все найденные.
        row = conn.execute('SELECT * FROM operations WHERE owner=%s AND key=%s', (user['username'], key)).fetchone()
        if row:
            # Прежний ключ должен соответствовать прежнему содержимому; иначе возвращается конфликт, а не повтор
            # чужого результата.
            if row['fingerprint'] != fingerprint:
                raise HTTPException(409, 'Этот Idempotency-Key уже использован с другим запросом')
            return Response(status_code=204) if row['status'] == 204 else JSONResponse(json.loads(row['response']), status_code=row['status'])

    # В той же транзакции сохраняет результат и fingerprint операции. Квитанция и изменение должны
    # фиксироваться вместе: нельзя подтвердить несохранённую запись.
    def receipt(conn, key, fingerprint, user, status, result):
        # NOTIFY относится к той же транзакции, что и задача/квитанция.
        # Повторы через replay не вызывают второе уведомление.
        record_id = result['id'] if result else fingerprint.split(':')[1]
        # SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; fetchone берёт
        # одну строку, fetchall — все найденные.
        conn.execute('SELECT pg_notify(%s,%s)', ('tasks_changed', json.dumps({
            'type': 'task.changed', 'event_id': str(uuid4()), 'owner': user['username'],
            'record_id': record_id, 'action': fingerprint.split(':')[0],
            'instance': instance, 'version': release['version']})))
        # INSERT сохраняет строку с параметрами отдельно от SQL. Ограничения таблицы дополнительно защищают
        # данные при конкурирующих запросах.
        conn.execute('INSERT INTO operations VALUES (%s,%s,%s,%s,%s)',
                     (user['username'], key, fingerprint, status, json.dumps(result)))
        return Response(status_code=204) if status == 204 else JSONResponse(result, status_code=status)

    # Проверяет повтор и UUID, создаёт запись с начальной версией, сохраняет квитанцию. Успешный ответ 201
    # и Location указывают на созданный ресурс.
    @app.post('/api/v1/tasks', status_code=201)
    def create(body: TaskCreate, user=Depends(writer), idempotency_key: str = Header(default='')):
        # Преобразуем проверенную модель в JSON-совместимые значения: даты/UUID станут строками. exclude_unset
        # сохраняет смысл частичного PATCH.
        values = body.model_dump(mode='json')
        # Fingerprint связывает ключ с методом, версией/адресом и телом. Иное содержимое с прежним ключом не
        # считается повтором.
        # Стабильная сериализация делает сравнение повторов независимым от порядка JSON-ключей клиента.
        fp = 'POST:' + json.dumps(values, sort_keys=True)
        # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
        # откатывает; ресурс освобождается при выходе.
        with db.connect() as conn:
            old = replay(conn, idempotency_key, fp, user)
            if old is not None:
                return old
            # Транзакционная блокировка сериализует одновременную инициализацию схемы. Освобождается при
            # завершении транзакции.
            conn.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,1))', (values['id'],))
            if conn.execute('SELECT 1 FROM tasks WHERE id=%s', (values['id'],)).fetchone():
                raise HTTPException(409, 'UUID уже существует')
            # INSERT сохраняет строку с параметрами отдельно от SQL. Ограничения таблицы дополнительно защищают
            # данные при конкурирующих запросах.
            conn.execute('INSERT INTO tasks VALUES (%s,%s,%s,%s,%s,%s,%s,%s,0)',
                (values['id'], user['username'], values['due_date'], values['title'],
                 values['status'], values['description'], 1, now()))
            result = task(owned(conn, body.id, user))
            response = receipt(conn, idempotency_key, fp, user, 201, result)
            response.headers['Location'] = '/api/v1/tasks/' + values['id']
            return response

    # Сравнивает If-Match с текущей версией. Несовпадение даёт 409 с серверной записью: клиент должен
    # разрешить конфликт, а не молча перезаписать чужую правку.
    def check_version(row, supplied):
        if supplied != '"' + str(row['version']) + '"':
            raise HTTPException(409, {'message': 'Запись изменилась на сервере', 'server': task(row)})

    # Применяет только переданные поля PATCH после проверки владельца, версии и ключа операции. version
    # увеличивается, квитанция обеспечивает безопасный повтор.
    @app.patch('/api/v1/tasks/{record_id}')
    def update(record_id: UUID, body: TaskPatch, user=Depends(writer),
               idempotency_key: str = Header(default=''), if_match: str = Header(default='')):
        # Преобразуем проверенную модель в JSON-совместимые значения: даты/UUID станут строками. exclude_unset
        # сохраняет смысл частичного PATCH.
        # Берём только явно переданные PATCH-поля. Значение по умолчанию схемы не должно случайно затереть
        # старое поле.
        changes = body.model_dump(mode='json', exclude_unset=True)
        if not changes or any(v is None for v in changes.values()):
            raise HTTPException(400, 'Передайте непустой набор полей без null')
        # Fingerprint связывает ключ с методом, версией/адресом и телом. Иное содержимое с прежним ключом не
        # считается повтором.
        fp = f'PATCH:{record_id}:{if_match}:' + json.dumps(changes, sort_keys=True)
        # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
        # откатывает; ресурс освобождается при выходе.
        with db.connect() as conn:
            old = replay(conn, idempotency_key, fp, user)
            if old is not None:
                return old
            row = owned(conn, record_id, user)
            check_version(row, if_match)
            # Tombstone сохраняет факт удаления для синхронизации; обычное чтение/правка удалённой записи
            # ограничены.
            if row['deleted']:
                raise HTTPException(409, {'message': 'Задача удалён на сервере', 'server': task(row)})
            # Объединяем старые поля с переданными PATCH. Непереданные значения остаются прежними, а не
            # сбрасываются в default.
            merged = dict(row) | changes
            # UPDATE изменяет строку внутри транзакции. Значения передаются параметрами; version/updated_at, когда
            # обновляются, позволяют обнаруживать устаревшие правки.
            conn.execute('UPDATE tasks SET due_date=%s,title=%s,status=%s,description=%s,version=version+1,updated_at=%s WHERE id=%s',
                         (merged['due_date'], merged['title'], merged['status'], merged['description'], now(), str(record_id)))
            return receipt(conn, idempotency_key, fp, user, 200, task(owned(conn, record_id, user)))

    # Ставит deleted вместо физического удаления и увеличивает version. Tombstone нужен клиентам,
    # пропустившим удаление offline. Ответ 204 не содержит тела.
    @app.delete('/api/v1/tasks/{record_id}', status_code=204)
    def delete(record_id: UUID, user=Depends(writer), idempotency_key: str = Header(default=''),
               if_match: str = Header(default='')):
        # Fingerprint связывает ключ с методом, версией/адресом и телом. Иное содержимое с прежним ключом не
        # считается повтором.
        fp = f'DELETE:{record_id}:{if_match}'
        # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
        # откатывает; ресурс освобождается при выходе.
        with db.connect() as conn:
            old = replay(conn, idempotency_key, fp, user)
            if old is not None:
                return old
            row = owned(conn, record_id, user)
            check_version(row, if_match)
            # UPDATE изменяет строку внутри транзакции. Значения передаются параметрами; version/updated_at, когда
            # обновляются, позволяют обнаруживать устаревшие правки.
            conn.execute('UPDATE tasks SET deleted=1,version=version+1,updated_at=%s WHERE id=%s', (now(), str(record_id)))
            return receipt(conn, idempotency_key, fp, user, 204, None)

    # Проверяет готовность БД и фонового слушателя. Балансировщик должен переключать трафик только на
    # действительно готовый процесс, а не просто открытый порт.
    @app.get('/ready')
    def readiness():
        try:
            # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
            # откатывает; ресурс освобождается при выходе.
            with db.connect() as conn:
                # SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; fetchone берёт
                # одну строку, fetchall — все найденные.
                conn.execute('SELECT 1')
            if not hub.ready.is_set():
                raise RuntimeError('listener unavailable')
        except Exception:
            raise HTTPException(503, 'Экземпляр временно не готов')
        return {'status': 'ready', 'instance': instance, 'version': release['version']}

    # Возвращает идентификатор экземпляра и версию релиза. По ним видно, какой backend обработал запрос
    # через общий адрес nginx.
    @app.get('/meta')
    def metadata():
        return {'instance': instance, **release}

    if 'summary' in release.get('features', []):
        # Дополнительная возможность новой версии: агрегирует записи владельца. Включение зависит от релиза,
        # поэтому blue и green различимы при демонстрации.
        @app.get('/api/v1/summary')
        def summary(user=Depends(current_user)):
            # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
            # откатывает; ресурс освобождается при выходе.
            with db.connect() as conn:
                # SELECT читает строки. Параметры связываются отдельно от SQL, защищая от инъекций; fetchone берёт
                # одну строку, fetchall — все найденные.
                row = conn.execute("SELECT count(*) AS count, COALESCE(sum(CASE WHEN status='done' THEN 1 ELSE 0 END),0) AS done FROM tasks WHERE owner=%s AND deleted=0", (user['username'],)).fetchone()
            return {'count': row['count'], 'done': int(row['done']), 'open': row['count'] - int(row['done'])}

    # Авторизует WebSocket, отправляет connected и события очереди пользователя/heartbeat. В finally
    # освобождает очередь. WSS сообщает об изменении, сами данные клиент читает через REST.
    @app.websocket('/api/v1/events')
    async def events(websocket: WebSocket):
        # QML WebSocket авторизуется первым кадром; Python-клиент — заголовком.
        accepted = False
        try:
            auth = websocket.headers.get('authorization', '')
            if not auth:
                # Подтверждаем переход к WebSocket. После accept ответы передаются кадрами, а не отдельными
                # HTTP-ответами.
                await websocket.accept()
                accepted = True
                frame = await asyncio.wait_for(websocket.receive_text(), timeout=8)
                if len(frame) > 4096:
                    raise ValueError()
                message = json.loads(frame)
                # Явно проверяем форму/тип JSON. Декодирование само по себе не гарантирует объект или число нужного
                # типа.
                if message.get('type') != 'authenticate' or not isinstance(message.get('token'), str):
                    raise ValueError()
                auth = 'Bearer ' + message['token']
            if not auth.startswith('Bearer '):
                raise ValueError()
            # Проверяем алгоритм, подпись и обязательные поля. Просто декодированный JSON не является
            # доказательством входа.
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
            # Подтверждаем переход к WebSocket. После accept ответы передаются кадрами, а не отдельными
            # HTTP-ответами.
            await websocket.accept()
        queue = asyncio.Queue(maxsize=64)
        hub.clients[queue] = claims['sub']
        try:
            # Отправляем JSON в это соединение. await ждёт освобождения транспорта, не блокируя весь сервер.
            await websocket.send_json({'type': 'connected', 'instance': instance, 'version': release['version']})
            # Цикл обслуживает поток сообщений/подключение до явного выхода или исключения. Это не создание нового
            # процесса на каждое сообщение.
            while True:
                if datetime.now(timezone.utc).timestamp() >= claims['exp']:
                    await websocket.close(code=1008, reason='token expired')
                    return
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=15)
                except asyncio.TimeoutError:
                    event = {'type': 'heartbeat'}
                # Отправляем JSON в это соединение. await ждёт освобождения транспорта, не блокируя весь сервер.
                await websocket.send_json(event)
        except (WebSocketDisconnect, RuntimeError, OSError):
            pass
        # Этот блок выполняется и при нормальном выходе, и при исключении: подходит для освобождения
        # ресурса/отписки.
        finally:
            hub.clients.pop(queue, None)

    # Корректирует описание API: убирает стандартный 422, поскольку собственная проверка возвращает 400.
    # Готовая схема кэшируется.
    def openapi():
        if app.openapi_schema is None:
            schema = get_openapi(title=app.title, version=app.version, description=app.description, routes=app.routes)
            # Стандартный FastAPI описывает 422, но наш обработчик возвращает 400.
            for path in schema['paths'].values():
                for operation in path.values():
                    # Явно проверяем форму/тип JSON. Декодирование само по себе не гарантирует объект или число нужного
                    # типа.
                    if isinstance(operation, dict):
                        operation.get('responses', {}).pop('422', None)
            app.openapi_schema = schema
        return app.openapi_schema
    app.openapi = openapi
    return app
