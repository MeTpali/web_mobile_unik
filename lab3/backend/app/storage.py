# Таблицы SQLite, транзакции и хеширование паролей. Серверное хранилище переживает рестарт. Параметры
# SQL передаются отдельно от текста; транзакция фиксирует связанные изменения вместе или откатывает их
# целиком.
"""Общая PostgreSQL для всех blue/green процессов. Схема совместима с обеими версиями."""
import hashlib
import os
import secrets
from contextlib import contextmanager

# Драйвер PostgreSQL выполняет SQL/транзакции; dict_row позволяет читать столбцы по имени.
import psycopg
# Драйвер PostgreSQL выполняет SQL/транзакции; dict_row позволяет читать столбцы по имени.
from psycopg.rows import dict_row


# Получает пароль и соль, возвращает PBKDF2-HMAC-SHA256 в hex. Соль различает хеши одинаковых паролей;
# 200 000 итераций замедляют перебор. Пароль в БД не сохраняется.
def password_hash(password: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 200_000).hex()


# Слой соединений и схемы серверной БД. Телефон обращается к REST, а не подключается к этой БД
# напрямую.
class Database:
    # Конструктор записывает состояние в self — текущий экземпляр. Эти поля останутся доступными другим
    # методам после выхода из функции.
    def __init__(self, dsn):
        self.dsn = dsn

    # Контекст соединения ограничивает транзакцию одной операцией. Успех фиксирует изменения, исключение
    # откатывает их; ресурс освобождается при выходе.
    @contextmanager
    def connect(self):
        # Отдельное соединение на транзакцию: соединения не разделяются между потоками.
        # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
        # откатывает; ресурс освобождается при выходе.
        with psycopg.connect(self.dsn, row_factory=dict_row, connect_timeout=3,
                             options='-c statement_timeout=5000') as conn:
            # contextmanager передаёт соединение вызывающему with-блоку. После его завершения управление вернётся
            # сюда для COMMIT/ROLLBACK/закрытия.
            yield conn
            # Контекст psycopg делает COMMIT при успехе и ROLLBACK при исключении.

    # Создаёт таблицы и учебные аккаунты при необходимости. Повторный/одновременный старт экземпляров не
    # должен стирать существующие данные.
    def initialize(self):
        # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
        # откатывает; ресурс освобождается при выходе.
        with self.connect() as db:
            # Одновременный старт нескольких systemd-инстансов не создаёт гонку DDL.
            # Транзакционная блокировка сериализует одновременную инициализацию схемы. Освобождается при
            # завершении транзакции.
            db.execute('SELECT pg_advisory_xact_lock(73103001)')
            # Таблица пользователей хранит соль, хеш и роль. IF NOT EXISTS не стирает данные при повторном
            # запуске.
            db.execute('''CREATE TABLE IF NOT EXISTS users (
                username TEXT PRIMARY KEY, salt TEXT NOT NULL,
                password_hash TEXT NOT NULL, role TEXT NOT NULL)''')
            # Таблица пользователей хранит соль, хеш и роль. IF NOT EXISTS не стирает данные при повторном
            # запуске.
            db.execute('''CREATE TABLE IF NOT EXISTS expenses (
                id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES users(username),
                date TEXT NOT NULL, category TEXT NOT NULL, amount_minor BIGINT NOT NULL,
                comment TEXT NOT NULL, version INTEGER NOT NULL, updated_at TEXT NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0)''')
            # Таблица квитанций хранит fingerprint и ответ операции. Пара owner/key уникальна: одинаковый ключ
            # разных пользователей не смешивает ответы.
            db.execute('''CREATE TABLE IF NOT EXISTS operations (
                owner TEXT NOT NULL, key TEXT NOT NULL, fingerprint TEXT NOT NULL,
                status INTEGER NOT NULL, response TEXT, PRIMARY KEY(owner,key))''')
            for name, role in [('demo', 'writer'), ('viewer', 'reader')]:
                # Соль участвует в хеше пароля и не является паролем. Случайность различает хеши одинаковых паролей.
                salt = secrets.token_hex(16)
                # INSERT сохраняет строку с параметрами отдельно от SQL. Ограничения таблицы дополнительно защищают
                # данные при конкурирующих запросах.
                db.execute('INSERT INTO users VALUES (%s,%s,%s,%s) ON CONFLICT DO NOTHING',
                           (name, salt, password_hash(os.getenv('LAB_DEMO_PASSWORD', 'demo12345'), salt), role))
