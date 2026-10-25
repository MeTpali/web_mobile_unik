"""Проверки диапазона и реального протокола через ASGI TestClient."""

import pytest
from fastapi.testclient import TestClient

from app.generator import InvalidRange, generate
from app.main import app


@pytest.mark.parametrize("minimum,maximum", [(1, 100), (-10, -1), (-10, 10), (-10**9, 10**9), (0, 0), (-10**9, -10**9), (10**9, 10**9)])
def test_ranges(minimum, maximum):
    for _ in range(100):
        result = generate(minimum, maximum)
        assert type(result["value"]) is int
        assert minimum <= result["value"] <= maximum


@pytest.mark.parametrize("minimum,maximum", [(None, 1), (True, 1), ("1", 2), (1.0, 2), (2, 1), (-10**9-1, 1), (0, 10**9+1)])
def test_invalid_ranges(minimum, maximum):
    with pytest.raises(InvalidRange):
        generate(minimum, maximum)


@pytest.mark.parametrize("message,code", [
    ('{', 'INVALID_JSON'), ('{"min": NaN}', 'INVALID_JSON'),
    ('[]', 'INVALID_REQUEST'), ('null', 'INVALID_REQUEST'),
    ('{}', 'UNKNOWN_TYPE'), ('{"type":"ping"}', 'UNKNOWN_TYPE'),
    ('{"type":"generate"}', 'INVALID_RANGE'),
    ('{"type":"generate","min":true,"max":2}', 'INVALID_RANGE'),
    ('{"type":"generate","min":2,"max":1}', 'INVALID_RANGE'),
    ('{"type":"generate","request_id":10}', 'INVALID_REQUEST'),
    ('{"type":"generate","extra":1}', 'INVALID_REQUEST'),
    (' ' * 4097, 'MESSAGE_TOO_LARGE'),
])
def test_errors_and_recovery(message, code):
    # После каждой ошибки соединение обязано оставаться пригодным для работы.
    with TestClient(app) as client, client.websocket_connect('/ws/random') as ws:
        ws.send_text(message)
        assert ws.receive_json()['error']['code'] == code
        ws.send_json({'type': 'generate', 'request_id': 'retry', 'min': 7, 'max': 7})
        assert ws.receive_json() == {'type': 'result', 'request_id': 'retry', 'min': 7, 'max': 7, 'value': 7}


def test_binary_and_independent_clients():
    with TestClient(app) as client:
        assert client.get('/health').json() == {'status': 'ok'}
        with client.websocket_connect('/ws/random') as first, client.websocket_connect('/ws/random') as second:
            first.send_bytes(b'hello')
            assert first.receive_json()['error']['code'] == 'UNSUPPORTED_FRAME'
            first.send_json({'type': 'generate', 'min': 1, 'max': 1})
            second.send_json({'type': 'generate', 'min': 2, 'max': 2})
            assert first.receive_json()['value'] == 1
            assert second.receive_json()['value'] == 2
        # После отключения можно открыть новое соединение.
        with client.websocket_connect('/ws/random') as ws:
            ws.send_json({'type': 'generate', 'request_id': 'bad', 'min': 9, 'max': 1})
            data = ws.receive_json()
            assert data['request_id'] == 'bad'
            assert data['type'] == 'error'
