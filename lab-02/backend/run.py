"""Запуск из папки backend: .venv/Scripts/python.exe run.py.

HOST/PORT можно задать в окружении. По умолчанию доступны все IPv4-интерфейсы.
Лимит транспорта 64 КБ защищает от огромных кадров; прикладной лимит — 4 КБ.
"""

import os

import uvicorn

# Защита точки входа: импорт файла не должен запускать сервер.
if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    if not 1 <= port <= 65535:
        raise ValueError("PORT должен быть от 1 до 65535")
    # auto выбирает установленную реализацию WebSocket и поддерживается
    # также версиями Uvicorn, чьи аннотации ещё не содержат websockets-sansio.
    # app.main:app — модуль и объект ASGI-приложения. 0.0.0.0 означает
    # прослушивание всех IPv4-интерфейсов, а не адрес для ввода на телефоне.
    uvicorn.run("app.main:app", host=os.environ.get("HOST", "0.0.0.0"), port=port,
                ws="auto", ws_max_size=65536, ws_max_queue=16)
