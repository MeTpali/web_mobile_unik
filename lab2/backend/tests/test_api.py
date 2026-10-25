"""Контракт API и сценарии, от которых зависит offline-синхронизация."""
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture
def client(tmp_path):
    app = create_app(tmp_path / 'db.sqlite', 'test-secret-' * 8)
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


def auth(c, user='demo'):
    r = c.post('/api/v1/auth/login', json={'username': user, 'password': 'demo12345'})
    assert r.status_code == 200
    return {'Authorization': 'Bearer ' + r.json()['access_token']}


def body():
    return {'id': str(uuid4()), 'date': '2026-10-25', 'category': 'Еда', 'amount_minor': 12550, 'comment': 'Обед'}


def mutation(h, version=None, key=None):
    return h | {'Idempotency-Key': key or str(uuid4())} | ({'If-Match': f'"{version}"'} if version else {})


def test_crud_cache_tombstones_and_restart(client):
    c = client
    h = auth(c)
    empty = c.get('/api/v1/expenses', headers=h)
    assert empty.json() == []
    assert empty.headers['cache-control'] == 'private, no-cache'
    assert 'last-modified' in empty.headers
    assert c.get('/api/v1/expenses', headers=h | {'If-None-Match': empty.headers['etag']}).status_code == 304
    assert c.get('/api/v1/expenses', headers=h | {'If-Modified-Since': empty.headers['last-modified']}).status_code == 304
    assert c.get('/api/v1/expenses', headers=h | {'If-None-Match': '"different"', 'If-Modified-Since': empty.headers['last-modified']}).status_code == 200
    data = body()
    created = c.post('/api/v1/expenses', json=data, headers=mutation(h))
    assert created.status_code == 201
    url = created.headers['location']
    get = c.get(url, headers=h)
    assert get.status_code == 200 and get.json()['amount_minor'] == 12550
    assert get.headers['etag'] == '"1"'
    assert c.get('/api/v1/expenses', headers=h | {'If-None-Match': empty.headers['etag']}).status_code == 200
    updated = c.patch(url, json={'category': 'Кафе'}, headers=mutation(h, 1))
    assert updated.status_code == 200 and updated.json()['version'] == 2
    conflict = c.patch(url, json={'category': 'Другое'}, headers=mutation(h, 1))
    assert conflict.status_code == 409 and conflict.json()['detail']['server']['version'] == 2
    assert c.delete(url, headers=mutation(h, 2)).status_code == 204
    assert c.get(url, headers=h).status_code == 404
    assert c.get('/api/v1/expenses', headers=h).json() == []
    tombstones = c.get('/api/v1/expenses?include_deleted=true', headers=h).json()
    assert len(tombstones) == 1 and tombstones[0]['deleted']
    # Новое приложение читает ту же БД: данные и удаления не теряются.
    restarted = TestClient(create_app(c.app.state.db.path, c.app.state.secret))
    assert restarted.get('/api/v1/expenses?include_deleted=true', headers=h).json() == tombstones


def test_lost_response_retry_is_exactly_once(client):
    c = client; h = auth(c); data = body(); create_headers = mutation(h)
    first = c.post('/api/v1/expenses', json=data, headers=create_headers)
    assert c.post('/api/v1/expenses', json=data, headers=create_headers).json() == first.json()
    url = '/api/v1/expenses/' + data['id']
    patch_headers = mutation(h, 1)
    r = c.patch(url, json={'comment': 'Изменено'}, headers=patch_headers)
    assert c.patch(url, json={'comment': 'Изменено'}, headers=patch_headers).json() == r.json()
    assert c.patch(url, json={'comment': 'Другое'}, headers=patch_headers).status_code == 409
    delete_headers = mutation(h, 2)
    assert c.delete(url, headers=delete_headers).status_code == 204
    assert c.delete(url, headers=delete_headers).status_code == 204
    assert c.get('/api/v1/expenses?include_deleted=true', headers=h).json()[0]['version'] == 3


def test_auth_permissions_and_invalid_data(client):
    c = client; h = auth(c)
    assert c.get('/api/v1/expenses').status_code == 401
    assert c.post('/api/v1/auth/login', json={'username': 'demo', 'password': 'bad'}).status_code == 401
    expired = jwt.encode({'sub': 'demo', 'exp': datetime.now(timezone.utc) - timedelta(seconds=1)}, c.app.state.secret, algorithm='HS256')
    assert c.get('/api/v1/expenses', headers={'Authorization': 'Bearer ' + expired}).status_code == 401
    viewer = auth(c, 'viewer')
    assert c.post('/api/v1/expenses', json=body(), headers=mutation(viewer)).status_code == 403
    data = body()
    c.post('/api/v1/expenses', json=data, headers=mutation(h))
    assert c.get('/api/v1/expenses/' + data['id'], headers=viewer).status_code == 404
    for changes in [{'amount_minor': 0}, {'amount_minor': 1.5}, {'amount_minor': True}, {'category': ' '}, {'date': '2026-02-30'}, {'extra': 1}]:
        assert c.post('/api/v1/expenses', json=body() | changes, headers=mutation(h)).status_code == 400
    assert c.get('/api/v1/expenses/not-uuid', headers=h).status_code == 400
    assert c.patch('/api/v1/expenses/' + data['id'], json={'category': None}, headers=mutation(h, 1)).status_code == 400
    assert c.post('/api/v1/expenses', content='broken', headers=mutation(h) | {'Content-Type': 'application/json'}).status_code == 400
    assert c.post('/api/v1/expenses', content='{}', headers=mutation(h)).status_code == 415


def test_server_failure_does_not_leak_details(client, monkeypatch):
    h = auth(client)
    @contextmanager
    def broken():
        raise sqlite3.OperationalError('private database details')
        yield
    monkeypatch.setattr(client.app.state.db, 'connect', broken)
    r = client.get('/api/v1/expenses', headers=h)
    assert r.status_code == 500
    assert r.json() == {'detail': 'Внутренняя ошибка сервера'}


def test_browser_and_openapi(client):
    assert 'Учёт расходов' in client.get('/').text
    assert client.get('/browser.js').status_code == 200
    schema = client.get('/openapi.json').json()
    assert '/api/v1/expenses/{record_id}' in schema['paths']
    statuses = schema['paths']['/api/v1/expenses']['post']['responses']
    assert '400' in statuses and '422' not in statuses


def test_generated_signing_key_survives_restart(tmp_path):
    path = tmp_path / 'db.sqlite'
    first = create_app(path)
    second = create_app(path)
    assert first.state.secret == second.state.secret
    assert (tmp_path / 'jwt.key').stat().st_mode & 0o777 == 0o600
