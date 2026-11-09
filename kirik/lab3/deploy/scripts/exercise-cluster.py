# Реальный сценарий отказа backend, обновления и отката под нагрузкой. Сценарий работает на
# компьютере, не телефоне. Blue/green — группы версий; готовность проверяется до переключения. Данные
# и секреты не должны сбрасываться при обновлении кода.
"""sudo /opt/kirik-tasks/venv/bin/python deploy/scripts/exercise-cluster.py

Реальное отключение backend, blue-green и откат под непрерывными HTTPS-запросами.
Использует только свои тестовые задачи. Секреты БД/JWT не читает.
"""
import json
import os
import ssl
import subprocess
import threading
import time
from collections import Counter
from pathlib import Path
from uuid import uuid4

import httpx
from websockets.sync.client import connect

ROOT = Path(__file__).resolve().parents[2]
TLS = ssl.create_default_context(cafile=str(ROOT / 'certificates/server.crt'))
URL = 'https://127.0.0.1:9543'


# Ограниченно ждёт условие готовности. Тайм-аут превращает зависший сценарий в диагностируемую ошибку
# вместо бесконечного цикла.
def wait(condition, message, timeout=40):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if condition():
            return
        time.sleep(0.15)
    raise AssertionError(message)


# Управляет конкретной systemd-службой стенда. Это реальный отказ/старт процесса, а не имитация ответа
# внутри теста.
def service(action, *names):
    subprocess.run(['systemctl', action, *['kirik-tasks@' + n for n in names]], check=True)


# Вызывает штатный сценарий переключения группы, чтобы испытание соответствовало реальным действиям
# администратора.
def switch(color):
    subprocess.run(['bash', str(ROOT / 'deploy/scripts/switch-release.sh'), color], check=True)


def main():
    if os.geteuid() != 0:
        raise SystemExit('Требуется sudo: тест останавливает и запускает только kirik-tasks@*.service')
    switch('blue')
    stop = threading.Event()
    counts, failures, events, connections, notifications = Counter(), [], [], [], []
    h = {}
    with httpx.Client(verify=TLS, timeout=6, trust_env=False) as c:
        login = c.post(URL + '/api/v1/auth/login', json={'username': 'demo', 'password': 'demo12345'})
        login.raise_for_status()
        h['Authorization'] = 'Bearer ' + login.json()['access_token']

        # Непрерывно отправляет HTTP-запросы во время отказа/переключения. Собирает backend и ошибки:
        # единичный успешный запрос после переключения не доказал бы отсутствие простоя.
        def monitor():
            with httpx.Client(verify=TLS, timeout=5, trust_env=False) as client:
                while not stop.is_set():
                    try:
                        r = client.get(URL + '/api/v1/tasks', headers=h)
                        r.raise_for_status()
                        backend = r.headers['x-backend-id'] + ' v' + r.headers['x-app-version']
                        counts[backend] += 1
                        events.append({'time': time.time(), 'backend': backend, 'status': r.status_code})
                    except Exception as exc:
                        failures.append(str(exc))
                    stop.wait(0.1)

        # Наблюдает WebSocket-события и переподключения во время отказа. Результаты сохраняются для проверки
        # восстановления доставки.
        def watch():
            while not stop.is_set():
                try:
                    # WebSocket-контекст закрывает сокет при выходе/ошибке. Это не SQL-транзакция;
                    # после разрыва внешний цикл попытается подключиться заново.
                    with connect('wss://127.0.0.1:9543/api/v1/events', ssl=TLS, additional_headers=h,
                                 open_timeout=5, close_timeout=2) as ws:
                        connected = json.loads(ws.recv(timeout=6))
                        connections.append(connected)
                        while not stop.is_set():
                            try:
                                value = json.loads(ws.recv(timeout=1))
                                if value.get('type') == 'task.changed':
                                    notifications.append(value)
                            except TimeoutError:
                                pass
                except Exception:
                    stop.wait(0.5)

        threads = [threading.Thread(target=monitor), threading.Thread(target=watch)]
        for t in threads:
            t.start()
        ids = []

        # Создаём собственную тестовую запись с уникальным id/ключом, запоминаем id для уборки
        # и ждём именно её push-событие. Это реальный запрос, а не прямое изменение БД.
        def create():
            data = {'id': str(uuid4()), 'due_date': '2026-10-25', 'title': 'Deployment test',
                    'status': "todo", 'description': 'temporary'}
            r = c.post(URL + '/api/v1/tasks', json=data, headers=h | {'Idempotency-Key': str(uuid4())})
            r.raise_for_status(); ids.append(data['id'])
            wait(lambda: any(e['record_id'] == data['id'] for e in notifications), 'Не получен push после мутации')
            return data['id']

        try:
            wait(lambda: bool(connections) and sum(counts.values()) >= 10, 'Нет исходного WebSocket/HTTPS')
            initial_node = connections[-1]['instance']
            print('Отключаем backend WebSocket:', initial_node, flush=True)
            service('stop', initial_node)
            wait(lambda: connections[-1]['instance'] != initial_node, 'WebSocket не переподключился')
            before = sum(counts.values())
            wait(lambda: sum(counts.values()) >= before + 20, 'REST не работает после отказа')
            create()
            service('start', initial_node)
            port = 9301 if initial_node == 'blue-1' else 9302
            # Проверяет готовность перед следующим шагом сценария, не подменяя её фиксированной короткой паузой.
            def ready():
                try:
                    return c.get(f'http://127.0.0.1:{port}/ready').status_code == 200
                except httpx.HTTPError:
                    return False
            wait(ready, 'Отключённый backend не восстановился')
            print('Переключаем blue → green', flush=True)
            switch('green')
            wait(lambda: c.get(URL + '/meta').json()['version'].startswith('2.'), 'Нет новой версии')
            # Новая версия добавляет summary; данные и старый токен остаются доступны.
            summary = c.get(URL + '/api/v1/summary', headers=h)
            assert summary.status_code == 200
            assert summary.json()['count'] == summary.json()['done'] + summary.json()['open']
            service('stop', 'blue-1', 'blue-2')
            wait(lambda: connections[-1]['instance'].startswith('green'), 'WS остался на остановленной группе')
            create()
            before = sum(counts.values())
            wait(lambda: sum(counts.values()) >= before + 20, 'Нет запросов к green')
            print('Откат green → blue', flush=True)
            switch('blue')
            wait(lambda: c.get(URL + '/meta').json()['version'].startswith('1.'), 'Откат не выполнен')
            assert c.get(URL + '/api/v1/summary', headers=h).status_code == 404
            service('stop', 'green-1', 'green-2')
            wait(lambda: connections[-1]['instance'].startswith('blue'), 'WS не восстановился после отката')
            create()
        # Этот блок выполняется и при нормальном выходе, и при исключении: подходит для освобождения
        # ресурса/отписки.
        finally:
            # Возвращаем blue даже при неудаче; старые задачи не трогаем.
            switch('blue')
            for record_id in ids:
                url = URL + '/api/v1/tasks/' + record_id
                r = c.get(url, headers=h)
                if r.status_code == 200:
                    c.delete(url, headers=h | {'If-Match': f'"{r.json()["version"]}"', 'Idempotency-Key': str(uuid4())})
            stop.set()
            for t in threads:
                t.join(timeout=10)
    result = {'requests': sum(counts.values()), 'backends': dict(counts), 'failures': failures,
              'ws_connections': connections, 'push_events': notifications, 'events': events}
    path = ROOT / 'docs/cluster-validation.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    if os.getenv('SUDO_UID'):
        os.chown(path.parent, int(os.environ['SUDO_UID']), int(os.environ['SUDO_GID']))
        os.chown(path, int(os.environ['SUDO_UID']), int(os.environ['SUDO_GID']))
    print(json.dumps({k: v for k, v in result.items() if k != 'events'}, ensure_ascii=False, indent=2))
    assert not failures, 'Во время демонстрации были неуспешные HTTPS-запросы'
    print('PASS: failover, push reconnect, blue-green, rollback, no HTTP downtime')


if __name__ == '__main__':
    main()
