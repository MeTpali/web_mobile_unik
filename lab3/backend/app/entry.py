"""Точка входа systemd: TLS завершается на nginx, Uvicorn слушает loopback."""
from .main import create_app

app = create_app()
