/** Тесты сетевого слоя клиента в Node.js, без React и настоящего браузера.
 * fetch подменяется mock-функцией: можно воспроизвести ошибки и зависший запрос.
 * t.mock восстанавливает подмены после теста, чтобы сценарии не влияли друг на друга.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { requestRandom } from '../src/api.js';

test('клиент отправляет диапазон и читает ответ сервера', async (t) => {
  // Проверяем не только ответ, но и адрес, метод и отправленное тело запроса.
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url, '/api/random');
    assert.equal(options.method, 'POST');
    assert.deepEqual(JSON.parse(options.body), { min: 1, max: 10 });
    // Стандартный объект Response ведёт себя как ответ fetch, но сеть не используется.
    return Response.json({ min: 1, max: 10, value: 4 });
  });
  assert.deepEqual(await requestRandom(1, 10), { min: 1, max: 10, value: 4 });
});

test('клиент обрабатывает HTTP-ошибки, неверный JSON и результат', async (t) => {
  // Пара «ответ / регулярное выражение сообщения». Включены HTTP-ошибки,
  // HTML вместо JSON, null, неверный диапазон, строка вместо числа и чужие границы.
  const cases = [
    [Response.json({ error: { message: 'Ошибка диапазона' } }, { status: 400 }), /Ошибка диапазона/],
    [Response.json({}, { status: 500 }), /HTTP 500/],
    [new Response('<html>error</html>'), /некорректный ответ/],
    [Response.json(null), /некорректный результат/],
    [Response.json({ min: 1, max: 10, value: 11 }), /некорректный результат/],
    [Response.json({ min: 1, max: 10, value: '5' }), /некорректный результат/],
    [Response.json({ min: 2, max: 10, value: 5 }), /некорректный результат/],
  ];
  const mock = t.mock.method(globalThis, 'fetch');
  for (const [response, message] of cases) {
    mock.mock.mockImplementation(async () => response);
    // rejects проверяет отклонённый Promise, а не синхронный throw.
    await assert.rejects(requestRandom(1, 10), message);
  }
});

// При отсутствии сети fetch отклоняется, HTTP-статуса в таком случае нет.
test('ошибка соединения объясняется пользователю', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => { throw new TypeError('Failed to fetch'); });
  await assert.rejects(requestRandom(1, 10), /Не удалось связаться с сервером/);
});

test('тайм-аут отменяет запрос и сообщает об истечении 10 секунд', async (t) => {
  // Виртуальные таймеры проверяют 10-секундное ожидание без реальной задержки теста.
  t.mock.timers.enable({ apis: ['setTimeout'] });
  t.mock.method(globalThis, 'fetch', (_url, { signal }) => new Promise((_resolve, reject) => {
    // Поддельный fetch «висит» до abort, как реальный незавершённый запрос.
    signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')));
  }));
  // Сначала начинаем ожидать отклонение, затем переводим виртуальное время вперёд.
  const check = assert.rejects(requestRandom(1, 10), /не ответил за 10 секунд/);
  t.mock.timers.tick(10_000);
  await check;
});
