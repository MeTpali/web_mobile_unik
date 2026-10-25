"""python run.py — HTTPS на всех IPv4-интерфейсах, порт 8543."""
import os
from pathlib import Path

import uvicorn
from app.main import create_app

if __name__ == '__main__':
    certs = Path(__file__).resolve().parents[1] / 'certificates'
    uvicorn.run(create_app(), host='0.0.0.0', port=int(os.getenv('PORT', '8543')),
                ssl_keyfile=str(certs / 'server.key'), ssl_certfile=str(certs / 'server.crt'))
