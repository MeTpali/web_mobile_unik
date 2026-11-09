# Точка входа systemd-инстанса. Импорты подключают зависимости; основной код выполняет одну роль в
# цепочке приложения.
"""Точка входа systemd: TLS завершается на nginx, Uvicorn слушает loopback."""
from .main import create_app

app = create_app()
