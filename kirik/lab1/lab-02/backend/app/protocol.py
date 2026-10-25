"""JSON-конверт сохраняет request_id и оставляет сокет открытым после ошибки."""
import json
from .calculator import calculate


def error(code, message, request_id=None):
    return {'type': 'error', 'request_id': request_id, 'error': {'code': code, 'message': message}}


def reject_constant(value):
    raise ValueError('JSON не поддерживает ' + value)


def handle_message(text):
    if len(text.encode()) > 4096:
        return error('MESSAGE_TOO_LARGE', 'Сообщение больше 4096 байт')
    try:
        data = json.loads(text, parse_constant=reject_constant)
    except (ValueError, RecursionError):
        return error('INVALID_JSON', 'Некорректный JSON')
    if not isinstance(data, dict):
        return error('INVALID_REQUEST', 'Ожидается JSON-объект')
    request_id = data.get('request_id')
    if request_id is not None and (not isinstance(request_id, str) or not 1 <= len(request_id) <= 64):
        return error('INVALID_REQUEST', 'Некорректный request_id')
    if data.get('type') != 'calculate':
        return error('UNKNOWN_TYPE', 'Ожидается type: calculate', request_id)
    if set(data) - {'type', 'request_id', 'a', 'b', 'operation'}:
        return error('INVALID_REQUEST', 'Неизвестные поля', request_id)
    try:
        return {'type': 'result', 'request_id': request_id,
                **calculate(data.get('a'), data.get('b'), data.get('operation'))}
    except ValueError as exc:
        return error('INVALID_OPERATION', str(exc), request_id)
