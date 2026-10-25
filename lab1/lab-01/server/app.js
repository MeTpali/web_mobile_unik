/** HTTP-слой: маршруты, разбор запроса, JSON-ответы и статические файлы.
 * Порядок middleware важен: Express проходит обработчики сверху вниз.
 * Здесь создаётся приложение, но порт открывает только server/index.js или тест.
 */
import express from 'express';
import { fileURLToPath } from 'node:url';
import { generateRandom, InvalidRangeError } from './random.js';

export const app = express();

// Диагностический маршрут для проверки сервера и proxy Vite.
app.get('/api/health', (_request, response) => {
  response.json({ status: 'ok' });
});

// Цепочка для POST: проверка Content-Type -> разбор JSON -> генерация.
// request содержит запрос, response формирует ответ; next передаёт управление дальше.
app.post('/api/random', (request, response, next) => {
  if (!request.is('application/json')) {
    // return прекращает этот обработчик, чтобы не отправить второй ответ.
    return response.status(415).json({
      error: { code: 'UNSUPPORTED_MEDIA_TYPE', message: 'Ожидается Content-Type: application/json' },
    });
  }
  next();
// 1 КБ достаточно для двух чисел. strict:false разрешает разбор любого JSON;
// проверку «должен быть объект» выполняет generateRandom с единым INVALID_RANGE.
}, express.json({ limit: '1kb', strict: false }), (request, response) => {
  response.set('Cache-Control', 'no-store'); // Результат генерации не следует сохранять в HTTP-кеше.
  // Синхронный throw из generateRandom перехватывает Express и передаёт error middleware.
  response.json(generateRandom(request.body));
});

// Сюда попадают запросы /api, для которых не нашлось обработчика выше.
// Размещено перед static, чтобы неизвестный API не превратился в HTML-страницу.
app.use('/api', (_request, response) => {
  response.status(404).json({
    error: { code: 'NOT_FOUND', message: 'API-маршрут не найден' },
  });
});

// URL вычисляется от этого модуля, а не от текущей папки терминала.
// fileURLToPath корректно преобразует URL с пробелами/кириллицей в путь Windows.
// dist создаётся Vite. express.static отдаёт index.html, CSS и JS, не генерируя их.
app.use(express.static(fileURLToPath(new URL('../dist/', import.meta.url))));

// Четыре аргумента нужны Express для распознавания обработчика ошибок.
app.use((error, _request, response, _next) => {
  // Без распознанной причины считаем ошибку непредвиденной и не раскрываем стек клиенту.
  // Имена с _ показывают неиспользуемые параметры, но сохраняют нужную сигнатуру.
  let status = 500;
  let code = 'INTERNAL_ERROR';
  let message = 'Внутренняя ошибка сервера';

  // Наш тип ошибки и служебные поля JSON-парсера переводим в контракт API.
  if (error instanceof InvalidRangeError) {
    status = 400;
    code = 'INVALID_RANGE';
    message = error.message;
  } else if (error.type === 'entity.parse.failed') {
    status = 400;
    code = 'INVALID_JSON';
    message = 'Некорректный JSON';
  } else if (error.type === 'entity.too.large') {
    status = 413;
    code = 'PAYLOAD_TOO_LARGE';
    message = 'Размер тела запроса не должен превышать 1 КБ';
  } else if (error.status === 415) {
    status = 415;
    code = 'UNSUPPORTED_MEDIA_TYPE';
    message = 'Неподдерживаемая кодировка запроса';
  } else {
    console.error(error);
  }

  // code удобен программам, message — пользователю. json задаёт тип ответа
  // application/json и сериализует объект. Подробности сбоя остаются в консоли.
  response.status(status).json({ error: { code, message } });
});
