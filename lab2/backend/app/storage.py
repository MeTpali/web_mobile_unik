"""SQLite сервера: транзакция объединяет изменение и квитанцию идемпотентности."""
import hashlib
import os
import secrets
import sqlite3
from contextlib import contextmanager
from pathlib import Path


def password_hash(password: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 200_000).hex()


class Database:
    def __init__(self, path: Path):
        self.path = path
        path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
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
                salt = secrets.token_hex(16)
                password = os.getenv('LAB_DEMO_PASSWORD', 'demo12345')
                db.execute('INSERT OR IGNORE INTO users VALUES (?,?,?,?)',
                           (name, salt, password_hash(password, salt), role))

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
        finally:
            db.close()
