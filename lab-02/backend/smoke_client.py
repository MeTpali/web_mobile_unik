"""Консольная проверка настоящего WebSocket без Flutter и без графического интерфейса."""

import argparse
import asyncio
import json

from websockets.asyncio.client import connect


async def check(url):
    # Тайм-аут не позволяет проверке навсегда зависнуть при неверном адресе.
    async with connect(url, open_timeout=5) as socket:
        for request_id, minimum, maximum in [("normal", 1, 100), ("same", -7, -7), ("error", 10, 1), ("recovery", 0, 0)]:
            await socket.send(json.dumps({"type": "generate", "request_id": request_id,
                                          "min": minimum, "max": maximum}))
            data = json.loads(await asyncio.wait_for(socket.recv(), timeout=5))
            assert data["request_id"] == request_id
            if minimum > maximum:
                assert data["error"]["code"] == "INVALID_RANGE"
            else:
                assert data["type"] == "result"
                assert minimum <= data["value"] <= maximum
            print(json.dumps(data, ensure_ascii=False))
    print("WebSocket: все проверки пройдены")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="ws://127.0.0.1:8000/ws/random")
    asyncio.run(check(parser.parse_args().url))
