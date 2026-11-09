# Настройки и зависимости компонента. Импорты подключают зависимости; основной код выполняет одну роль
# в цепочке приложения.
"""python run.py — HTTPS на всех IPv4-интерфейсах, порт 8543."""
import os
from pathlib import Path

import uvicorn
from app.main import create_app

if __name__ == '__main__':
    certs = Path(__file__).resolve().parents[1] / 'certificates'
    # Uvicorn начинает обслуживание FastAPI. 0.0.0.0 слушает все интерфейсы ПК; заданная пара
    # сертификата/ключа включает TLS.
    uvicorn.run(create_app(), host='0.0.0.0', port=int(os.getenv('PORT', '8543')),
                ssl_keyfile=str(certs / 'server.key'), ssl_certfile=str(certs / 'server.crt'))
