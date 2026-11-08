# Межпроцессная доставка событий PostgreSQL в WebSocket. Цепочка событий: COMMIT → PostgreSQL NOTIFY →
# слушатель процесса → очередь пользователя → WSS. Клиент получает событие и перечитывает REST-снимок.
"""Каждый процесс слушает общий PostgreSQL-канал и обслуживает свои WebSockets."""
# asyncio управляет задачами и очередями; await отдаёт управление циклу событий, пока операция не
# готова.
import asyncio
import json
import logging
from contextlib import asynccontextmanager, suppress

# Драйвер PostgreSQL выполняет SQL/транзакции; dict_row позволяет читать столбцы по имени.
import psycopg


# Узел доставки внутри процесса: PostgreSQL связывает разные backend, очереди связывают этот процесс
# со своими WSS-клиентами.
class PushHub:
    # Конструктор записывает состояние в self — текущий экземпляр. Эти поля останутся доступными другим
    # методам после выхода из функции.
    def __init__(self, dsn):
        self.dsn = dsn
        self.clients = {}  # очередь -> имя пользователя
        self.ready = asyncio.Event()

    # Раскладывает события по очередям владельцев. Чужие события не выдаются; при переполнении
    # отправляется resync вместо бесконечного накопления — клиент перечитает REST-снимок.
    def deliver(self, event):
        for queue, owner in list(self.clients.items()):
            # Проверка владельца выполняется сервером. Скрыть строку только в UI недостаточно для разграничения
            # доступа.
            if event.get('owner') not in (None, owner):
                continue
            # Владелец используется сервером для маршрутизации, но удаляется из публичного события.
            public = {k: v for k, v in event.items() if k != 'owner'}
            # При перегрузке достаточно resync: полный снимок восстановит состояние, очередь не должна расти
            # бесконечно.
            if queue.full():
                # При перегрузке достаточно запросить полный снимок; данные в REST/БД.
                while not queue.empty():
                    # Освобождаем устаревшие события переполненной очереди: их заменит один запрос полного обновления.
                    queue.get_nowait()
                public = {'type': 'resync'}
            # Добавляем событие без ожидания медленного клиента. Очередь ограничена и проверена выше.
            queue.put_nowait(public)

    # Слушает PostgreSQL LISTEN/NOTIFY. После переподключения просит перечитать снимок: события во время
    # разрыва могли потеряться. CancelledError завершает задачу при остановке.
    async def listen(self):
        # Цикл обслуживает поток сообщений/подключение до явного выхода или исключения. Это не создание нового
        # процесса на каждое сообщение.
        while True:
            try:
                # Контекст ограничивает время соединения/транзакции блоком. Успех фиксирует изменения, исключение
                # откатывает; ресурс освобождается при выходе.
                async with await psycopg.AsyncConnection.connect(self.dsn, autocommit=True,
                        connect_timeout=3, keepalives=1, keepalives_idle=10,
                        keepalives_interval=3, keepalives_count=3) as conn:
                    await conn.execute('LISTEN tasks_changed')
                    # Слушатель PostgreSQL готов. Это событие разрешает завершить startup/lifespan.
                    self.ready.set()
                    # После разрыва слушателя события могли быть пропущены.
                    # После восстановления связи нельзя воспроизвести пропущенные NOTIFY. Просим клиентов получить полный
                    # снимок.
                    self.deliver({'type': 'resync'})
                    async for notification in conn.notifies():
                        try:
                            self.deliver(json.loads(notification.payload))
                        except (ValueError, TypeError):
                            logging.exception('Некорректное межпроцессное событие')
            except asyncio.CancelledError:
                raise
            except psycopg.Error:
                # Сбрасываем готовность межпроцессной доставки: readiness не должен продолжать утверждать, что
                # слушатель работает.
                self.ready.clear()
                logging.exception('LISTEN временно недоступен; повтор через 2 секунды')
                # Асинхронная пауза перед повтором LISTEN не блокирует обработку HTTP/WSS остальных задач.
                await asyncio.sleep(2)

    # Запускает фонового слушателя до обработки запросов, ждёт готовности, затем при остановке отменяет
    # задачу и ждёт её завершения.
    @asynccontextmanager
    async def lifespan(self, app):
        # Запускаем фоновую корутину. Ссылку на задачу сохраняем, чтобы отменить и дождаться её при остановке.
        task = asyncio.create_task(self.listen())
        try:
            await asyncio.wait_for(self.ready.wait(), timeout=10)
            yield
        # Этот блок выполняется и при нормальном выходе, и при исключении: подходит для освобождения
        # ресурса/отписки.
        finally:
            # Запрашиваем отмену слушателя. Затем await нужен, чтобы он успел освободить соединение до остановки
            # приложения.
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task
