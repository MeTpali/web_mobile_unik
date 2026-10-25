"""Непрерывные HTTPS-запросы во время отказа/blue-green. Ctrl+C выводит итог."""
import argparse
import json
import ssl
import time
from collections import Counter
from pathlib import Path

import httpx

p = argparse.ArgumentParser()
p.add_argument('--url', default='https://127.0.0.1:9443')
p.add_argument('--seconds', type=int, default=120)
p.add_argument('--output', type=Path)
args = p.parse_args()
tls = ssl.create_default_context(cafile=str(Path(__file__).resolve().parents[1] / 'certificates/server.crt'))
counts, failures, events = Counter(), [], []
started = time.monotonic()
with httpx.Client(verify=tls, timeout=5, trust_env=False) as client:
    login = client.post(args.url + '/api/v1/auth/login', json={'username': 'demo', 'password': 'demo12345'})
    login.raise_for_status()
    auth = {'Authorization': 'Bearer ' + login.json()['access_token']}
    try:
        while time.monotonic() - started < args.seconds:
            stamp = round(time.monotonic() - started, 2)
            try:
                r = client.get(args.url + '/api/v1/expenses', headers=auth)
                r.raise_for_status()
                info = r.headers.get('x-backend-id', '?') + ' v' + r.headers.get('x-app-version', '?')
                counts[info] += 1
                events.append({'second': stamp, 'backend': info, 'status': r.status_code})
                print(f'{stamp:6.2f}s HTTP {r.status_code} {info}', flush=True)
            except Exception as exc:
                failures.append({'second': stamp, 'error': str(exc)})
                print(f'{stamp:6.2f}s ERROR {exc}', flush=True)
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
result = {'requests': sum(counts.values()), 'backends': dict(counts), 'failures': failures, 'events': events}
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
print(json.dumps({k: v for k, v in result.items() if k != 'events'}, ensure_ascii=False, indent=2))
raise SystemExit(bool(failures))
