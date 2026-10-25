"""Интеграционные проверки настоящих systemd-инстансов и PostgreSQL.

Перед запуском нужен install-host.sh. Тестовые записи имеют случайные UUID,
удаляются в finally; пользовательские задачи не изменяются.
"""
import json
import ssl
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from uuid import uuid4

import httpx
import pytest
from websockets.sync.client import connect

CERT = Path(__file__).resolve().parents[2] / 'certificates/server.crt'
TLS = ssl.create_default_context(cafile=str(CERT))
PUBLIC = 'https://127.0.0.1:9543'
A, B = 'http://127.0.0.1:9301', 'http://127.0.0.1:9302'


@pytest.fixture
def client():
    with httpx.Client(verify=TLS, timeout=8, trust_env=False) as c:
        yield c


def auth(c, user='demo'):
    r = c.post(A + '/api/v1/auth/login', json={'username': user, 'password': 'demo12345'})
    r.raise_for_status()
    return {'Authorization': 'Bearer ' + r.json()['access_token']}


def record():
    return {'id': str(uuid4()), 'due_date': '2026-10-25', 'title': 'Cluster test', 'status': "todo", 'description': 'temporary'}


def headers(auth, version=None, key=None):
    return auth | {'Idempotency-Key': key or str(uuid4())} | ({'If-Match': f'"{version}"'} if version else {})


def clean(c, data, h):
    url = PUBLIC + '/api/v1/tasks/' + data['id']
    r = c.get(url, headers=h)
    if r.status_code == 200:
        assert c.delete(url, headers=headers(h, r.json()['version'])).status_code == 204


def event(ws, record_id):
    for _ in range(20):
        value = json.loads(ws.recv(timeout=6))
        if value.get('type') == 'task.changed' and value['record_id'] == record_id:
            return value
    raise AssertionError('Нет ожидаемого push-события')


def test_balancing_and_shared_auth(client):
    h = auth(client)
    seen = set()
    for _ in range(20):
        r = client.get(PUBLIC + '/api/v1/tasks', headers=h)
        assert r.status_code == 200
        seen.add(r.headers['x-backend-id'])
    assert seen == {'blue-1', 'blue-2'}
    assert client.get(A + '/ready').status_code == 200
    assert client.get(B + '/ready').status_code == 200


def test_parallel_idempotency_and_version_lock(client):
    h = auth(client); data = record(); key = headers(h)
    def create(base):
        return client.post(base + '/api/v1/tasks', json=data, headers=key)
    try:
        with ThreadPoolExecutor(2) as pool:
            responses = list(pool.map(create, [A, B]))
        assert [r.status_code for r in responses] == [201, 201]
        assert responses[0].json() == responses[1].json()
        url = '/api/v1/tasks/' + data['id']
        def patch(base):
            return client.patch(base + url, json={'description': base}, headers=headers(h, 1))
        with ThreadPoolExecutor(2) as pool:
            changes = list(pool.map(patch, [A, B]))
        assert sorted(r.status_code for r in changes) == [200, 409]
        assert client.get(B + url, headers=h).json()['version'] == 2
    finally:
        clean(client, data, h)


def test_cross_backend_push_and_user_isolation(client):
    h = auth(client); reader = auth(client, 'viewer'); data = record()
    try:
        # WebSocket на blue-2, мутация на blue-1: событие обязано пройти через БД.
        with connect('ws://127.0.0.1:9302/api/v1/events', additional_headers=h) as ws, \
             connect('ws://127.0.0.1:9301/api/v1/events', additional_headers=reader) as other:
            assert json.loads(ws.recv(timeout=5))['instance'] == 'blue-2'
            assert json.loads(other.recv(timeout=5))['type'] == 'connected'
            assert client.post(A + '/api/v1/tasks', json=data, headers=headers(h)).status_code == 201
            message = event(ws, data['id'])
            assert message['instance'] == 'blue-1' and 'owner' not in message
            with pytest.raises(TimeoutError):
                other.recv(timeout=0.4)
    finally:
        clean(client, data, h)


def test_wss_first_frame_auth_and_cache(client):
    h = auth(client); data = record()
    try:
        with connect('wss://127.0.0.1:9543/api/v1/events', ssl=TLS) as ws:
            ws.send(json.dumps({'type': 'authenticate', 'token': h['Authorization'][7:]}))
            assert json.loads(ws.recv(timeout=5))['type'] == 'connected'
            assert client.post(PUBLIC + '/api/v1/tasks', json=data, headers=headers(h)).status_code == 201
            assert event(ws, data['id'])['action'] == 'POST'
        r = client.get(PUBLIC + '/api/v1/tasks', headers=h)
        assert client.get(PUBLIC + '/api/v1/tasks', headers=h | {'If-None-Match': r.headers['etag']}).status_code == 304
    finally:
        clean(client, data, h)


def test_permissions_and_schema(client):
    assert client.get(PUBLIC + '/api/v1/tasks').status_code == 401
    assert client.post(PUBLIC + '/api/v1/tasks', json=record(), headers=headers(auth(client, 'viewer'))).status_code == 403
    assert '/api/v1/tasks/{record_id}' in client.get(PUBLIC + '/openapi.json').json()['paths']
