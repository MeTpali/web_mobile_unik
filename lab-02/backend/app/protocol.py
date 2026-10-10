"""Разбор текстового сообщения WebSocket и формирование одного ответа.

Ошибки клиента являются обычными ответами и не разрывают соединение.
request_id позволяет будущему Flutter-клиенту сопоставить запрос и результат.
"""

import json

from .generator import InvalidRange, generate

MAX_MESSAGE_BYTES = 4096


def error(code: str, message: str, request_id=None) -> dict:
    """Единый конверт ошибок; неизвестный идентификатор передаётся как null."""
    return {"type": "error", "request_id": request_id,
            "error": {"code": code, "message": message}}


def reject_constant(value):
    """JSON не разрешает NaN/Infinity, хотя стандартный json.loads их принимает."""
    raise ValueError(f"Недопустимая JSON-константа: {value}")


def handle_message(text: str) -> dict:
    """Протокол: generate + min/max + необязательный строковый request_id."""
    if len(text.encode("utf-8")) > MAX_MESSAGE_BYTES:
        return error("MESSAGE_TOO_LARGE", "Сообщение не должно превышать 4096 байт")
    try:
        data = json.loads(text, parse_constant=reject_constant)
    except (ValueError, RecursionError):
        return error("INVALID_JSON", "Некорректный JSON")
    if not isinstance(data, dict):
        return error("INVALID_REQUEST", "Сообщение должно быть JSON-объектом")

    request_id = data.get("request_id")
    if request_id is not None and (not isinstance(request_id, str) or not 1 <= len(request_id) <= 64):
        return error("INVALID_REQUEST", "request_id должен быть строкой длиной от 1 до 64 символов или null")
    if data.get("type") != "generate":
        return error("UNKNOWN_TYPE", "Поддерживается только type: generate", request_id)
    if set(data) - {"type", "request_id", "min", "max"}:
        return error("INVALID_REQUEST", "Сообщение содержит неизвестные поля", request_id)
    try:
        result = generate(data.get("min"), data.get("max"))
    except InvalidRange as exc:
        return error("INVALID_RANGE", str(exc), request_id)
    return {"type": "result", "request_id": request_id, **result}
