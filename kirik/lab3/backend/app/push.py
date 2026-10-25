"""Каждый процесс слушает общий PostgreSQL-канал и обслуживает свои WebSockets."""
import asyncio
import json
import logging
from contextlib import asynccontextmanager, suppress

import psycopg


class PushHub:
    def __init__(self, dsn):
        self.dsn = dsn
        self.clients = {}  # очередь -> имя пользователя
        self.ready = asyncio.Event()

    def deliver(self, event):
        for queue, owner in list(self.clients.items()):
            if event.get('owner') not in (None, owner):
                continue
            public = {k: v for k, v in event.items() if k != 'owner'}
            if queue.full():
                # При перегрузке достаточно запросить полный снимок; данные в REST/БД.
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
                    await conn.execute('LISTEN tasks_changed')
                    self.ready.set()
                    # После разрыва слушателя события могли быть пропущены.
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
