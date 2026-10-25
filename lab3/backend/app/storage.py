"""Общая PostgreSQL для всех blue/green процессов. Схема совместима с обеими версиями."""
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
        # Отдельное соединение на транзакцию: соединения не разделяются между потоками.
        with psycopg.connect(self.dsn, row_factory=dict_row, connect_timeout=3,
                             options='-c statement_timeout=5000') as conn:
            yield conn
            # Контекст psycopg делает COMMIT при успехе и ROLLBACK при исключении.

    def initialize(self):
        with self.connect() as db:
            # Одновременный старт нескольких systemd-инстансов не создаёт гонку DDL.
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
