# Таблицы SQLite, транзакции и хеширование паролей. Серверное хранилище переживает рестарт. Параметры
# SQL передаются отдельно от текста; транзакция фиксирует связанные изменения вместе или откатывает их
# целиком.
"""SQLite сервера: транзакция объединяет изменение и квитанцию идемпотентности."""
import hashlib
import os
import secrets
import sqlite3
from contextlib import contextmanager
from pathlib import Path


# Получает пароль и соль, возвращает PBKDF2-HMAC-SHA256 в hex. Соль различает хеши одинаковых паролей;
# 200 000 итераций замедляют перебор. Пароль в БД не сохраняется.
def password_hash(password: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 200_000).hex()


# Слой соединений и схемы серверной БД. Телефон обращается к REST, а не подключается к этой БД
# напрямую.
class Database:
    # Конструктор записывает состояние в self — текущий экземпляр. Эти поля останутся доступными другим
    # методам после выхода из функции.
    def __init__(self, path: Path):
        self.path = path
        path.parent.mkdir(parents=True, exist_ok=True)
        # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
        # откатывает; ресурс освобождается при выходе.
        with self.connect() as db:
            # Одним SQL-скриптом создаём users, сущности и operations. id — ключ записи, owner — аккаунт, version
            # — защита от устаревшей правки, deleted — tombstone, operations — квитанции повторов.
            db.executescript('''
                CREATE TABLE IF NOT EXISTS users (
                  username TEXT PRIMARY KEY, salt TEXT NOT NULL,
                  password_hash TEXT NOT NULL, role TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS expenses (
                  id TEXT PRIMARY KEY, owner TEXT NOT NULL, date TEXT NOT NULL,
                  category TEXT NOT NULL, amount_minor INTEGER NOT NULL,
                  comment TEXT NOT NULL, version INTEGER NOT NULL,
                  updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS operations (
                  owner TEXT NOT NULL, key TEXT NOT NULL, fingerprint TEXT NOT NULL,
                  status INTEGER NOT NULL, response TEXT,
                  PRIMARY KEY(owner, key));
            ''')
            # Учебные аккаунты создаются только при первом старте базы.
            for name, role in [('demo', 'writer'), ('viewer', 'reader')]:
                # Соль участвует в хеше пароля и не является паролем. Случайность различает хеши одинаковых паролей.
                salt = secrets.token_hex(16)
                password = os.getenv('LAB_DEMO_PASSWORD', 'demo12345')
                # INSERT сохраняет строку с параметрами отдельно от SQL. Ограничения таблицы дополнительно защищают
                # данные при конкурирующих запросах.
                db.execute('INSERT OR IGNORE INTO users VALUES (?,?,?,?)',
                           (name, salt, password_hash(password, salt), role))

    # Контекст соединения ограничивает транзакцию одной операцией. Успех фиксирует изменения, исключение
    # откатывает их; ресурс освобождается при выходе.
    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        try:
            # BEGIN IMMEDIATE исключает гонку проверки версии и записи.
            db.execute('BEGIN IMMEDIATE')
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        # Этот блок выполняется и при нормальном выходе, и при исключении: подходит для освобождения
        # ресурса/отписки.
        finally:
            db.close()
