# API и сетевые обработчики: маршруты, формат обмена и ошибки. Путь данных: JSON → схема →
# пользователь/права → транзакция → ответ. Depends передаёт проверенные зависимости обработчику; UI
# телефона не выполняет серверный SQL.
"""FastAPI отвечает за HTTP-диагностику и постоянное WebSocket-соединение."""

import logging

# FastAPI задаёт приложение, маршруты, HTTP-ответы и Depends. Импорт ещё не запускает сервер.
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from .protocol import error, handle_message

logger = logging.getLogger(__name__)
app = FastAPI(title="ЛР1 · вариант 1 · Калькулятор", version="1.0.0")


# Лёгкая проверка, что процесс отвечает. Она не выполняет пользовательскую операцию и не заменяет
# проверку готовности БД.
@app.get("/health")
async def health():
    """HTTP-проверка доступности; сама генерация использует только WebSocket."""
    return {"status": "ok"}


# Декоратор связывает URL с обработчиком WebSocket. Для телефона URL
# включает адрес ПК и порт: ws://<IP-ПК>:8100/ws/calculate.
# Принимает WebSocket калькулятора и обрабатывает каждый кадр отдельно. Сетевое отключение отличается
# от ошибки вычисления.
@app.websocket("/ws/calculate")
async def calculator_socket(websocket: WebSocket):
    """Один запрос — один ответ отправителю; состояние между клиентами не общее."""
    # Завершаем handshake: после accept можно читать и писать кадры.
    # Подтверждаем переход к WebSocket. После accept ответы передаются кадрами, а не отдельными
    # HTTP-ответами.
    await websocket.accept()
    try:
        # Цикл обслуживает несколько запросов по одному соединению.
        # await при ожидании кадра позволяет обслуживать другие соединения.
        # Цикл обслуживает поток сообщений/подключение до явного выхода или исключения. Это не создание нового
        # процесса на каждое сообщение.
        while True:
            # Низкоуровневый receive позволяет корректно различить text/binary
            # и штатное закрытие, не обрушая соединение из-за бинарного сообщения.
            event = await websocket.receive()
            if event["type"] == "websocket.disconnect":
                break
            if event.get("text") is None:
                # Отправляем JSON в это соединение. await ждёт освобождения транспорта, не блокируя весь сервер.
                await websocket.send_json(error("UNSUPPORTED_FRAME", "Отправляйте текстовый JSON, не бинарные данные"))
                continue
            try:
                # Протокол отделён от FastAPI: его можно тестировать без сети.
                response = handle_message(event["text"])
            except Exception:
                # Непредвиденный сбой записывается в журнал без раскрытия стека клиенту.
                logger.exception("Ошибка обработки WebSocket-сообщения")
                # Отправляем JSON в это соединение. await ждёт освобождения транспорта, не блокируя весь сервер.
                await websocket.send_json(error("INTERNAL_ERROR", "Внутренняя ошибка сервера"))
                await websocket.close(code=1011)
                return
            # Отправляем ответ только текущему клиенту; рассылки и общей
            # истории здесь нет. FastAPI сам сериализует словарь в JSON.
            # Отправляем JSON в это соединение. await ждёт освобождения транспорта, не блокируя весь сервер.
            await websocket.send_json(response)
    except WebSocketDisconnect:
        # Отключение телефона — нормальное завершение обработчика.
        pass
