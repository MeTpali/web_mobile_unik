/** Интеграционные тесты: настоящий HTTP-сервер и fetch без браузера.
 * Проверяют совместную работу маршрутов, JSON-парсера, генератора и ошибок.
 * Импорт app не запускает основной сервер на 3000 — тест управляет им сам.
 */
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { app } from '../server/app.js';

let server;
let base;
// before запускается перед тестами файла. Порт 0 просит ОС выбрать свободный
// порт, чтобы проверка не конфликтовала с запущенным приложением пользователя.
before(async () => {
  server = app.listen(0, '127.0.0.1');
  // Превращаем события Node.js в Promise: ждём готовности либо ошибки запуска.
  await new Promise((resolve, reject) => {
    server.once('listening', resolve);
    server.once('error', reject);
  });
  base = `http://127.0.0.1:${server.address().port}`;
});
// После проверок закрываем порт, иначе активный сервер удерживал бы процесс.
after(async () => {
  if (server) await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
});

// Тело принимается уже как текст: так можно послать намеренно испорченный JSON.
function post(body, contentType = 'application/json') {
  return fetch(`${base}/api/random`, {
    method: 'POST', headers: { 'Content-Type': contentType }, body,
  });
}

// Равные границы делают проверку воспроизводимой, несмотря на случайную природу API.
test('POST возвращает диапазон и результат', async () => {
  const response = await post(JSON.stringify({ min: 7, max: 7 }));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(), { min: 7, max: 7, value: 7 });
});

test('ошибки запроса имеют правильный статус и единый JSON-формат', async () => {
  // Таблица: [тело, ожидаемый статус, код ошибки, необязательный Content-Type].
  // Один цикл проверяет контракт каждой ошибки, а не только наличие исключения.
  const cases = [
    ['{}', 400, 'INVALID_RANGE'],
    ['{"min":2,"max":1}', 400, 'INVALID_RANGE'],
    ['{"min":"1","max":2}', 400, 'INVALID_RANGE'],
    ['{"min":null,"max":2}', 400, 'INVALID_RANGE'],
    ['{"min":false,"max":2}', 400, 'INVALID_RANGE'],
    ['{"min":0.5,"max":2}', 400, 'INVALID_RANGE'],
    ['{"min":0,"max":1000000001}', 400, 'INVALID_RANGE'],
    ['[]', 400, 'INVALID_RANGE'],
    ['null', 400, 'INVALID_RANGE'],
    ['', 400, 'INVALID_RANGE'],
    ['{', 400, 'INVALID_JSON'],
    [JSON.stringify({ padding: 'x'.repeat(1100) }), 413, 'PAYLOAD_TOO_LARGE'],
    ['{}', 415, 'UNSUPPORTED_MEDIA_TYPE', 'text/plain'],
  ];
  for (const [body, status, code, type] of cases) {
    const response = await post(body, type);
    assert.equal(response.status, status, body);
    assert.match(response.headers.get('content-type'), /application\/json/);
    const payload = await response.json();
    assert.equal(payload.error.code, code);
    assert.equal(typeof payload.error.message, 'string');
    assert.ok(payload.error.message.length > 0);
    // Подробный стек относится к серверной диагностике, а не публичному ответу.
    assert.equal(payload.error.stack, undefined);
  }
});

// Дополнительно убеждаемся, что служебный маршрут работает, а неизвестный
// API-адрес возвращает JSON 404, а не случайную HTML-страницу.
test('диагностика и неизвестный API-маршрут', async () => {
  const health = await fetch(`${base}/api/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { status: 'ok' });
  const missing = await fetch(`${base}/api/missing`);
  assert.equal(missing.status, 404);
  assert.equal((await missing.json()).error.code, 'NOT_FOUND');
});
