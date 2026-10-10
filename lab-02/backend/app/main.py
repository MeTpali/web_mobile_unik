"""FastAPI отвечает за HTTP-диагностику и постоянное WebSocket-соединение."""

import logging

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from .protocol import error, handle_message

logger = logging.getLogger(__name__)
app = FastAPI(title="Лабораторная № 2 — генератор случайных чисел", version="1.0.0")


@app.get("/health")
async def health():
    """HTTP-проверка доступности; сама генерация использует только WebSocket."""
    return {"status": "ok"}


@app.websocket("/ws/random")
async def random_socket(websocket: WebSocket):
    """Один запрос — один ответ отправителю; состояние между клиентами не общее."""
    await websocket.accept()
    try:
        while True:
            # Низкоуровневый receive позволяет корректно различить text/binary
            # и штатное закрытие, не обрушая соединение из-за бинарного сообщения.
            event = await websocket.receive()
            if event["type"] == "websocket.disconnect":
                break
            if event.get("text") is None:
                await websocket.send_json(error("UNSUPPORTED_FRAME", "Отправляйте текстовый JSON, не бинарные данные"))
                continue
            try:
                response = handle_message(event["text"])
            except Exception:
                # Непредвиденный сбой записывается в журнал без раскрытия стека клиенту.
                logger.exception("Ошибка обработки WebSocket-сообщения")
                await websocket.send_json(error("INTERNAL_ERROR", "Внутренняя ошибка сервера"))
                await websocket.close(code=1011)
                return
            await websocket.send_json(response)
    except WebSocketDisconnect:
        # Отключение телефона — нормальное завершение обработчика.
        pass
