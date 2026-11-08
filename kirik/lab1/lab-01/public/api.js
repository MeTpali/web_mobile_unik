// HTTP-транспорт или обработка действий пользователя. Импорты подключают зависимости; основной код
// выполняет одну роль в цепочке приложения.
/* HTTP-сервис не зависит от DOM: получает JSON и возвращает результат через callback. */
var CalculatorApi = (function () {
  'use strict';
  // Асинхронный XMLHttpRequest не блокирует интерфейс во время ожидания сети.
  // Общий HTTP-транспорт задаёт заголовки и обрабатывает ответ/сбой. busy защищает форму от
  // конкурирующих отправок.
  function request(data, done) {
    // Асинхронный HTTP-клиент старого браузера. Ответ придёт в callback, не блокируя страницу.
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/calculate'); xhr.timeout = 10000;
    xhr.setRequestHeader('Content-Type', 'application/json');
    // onload означает получение ответа, даже HTTP-ошибки. Успех отдельно определяется диапазоном 2xx.
    xhr.onload = function () {
      try {
        // Разбираем ответ; ошибку JSON нужно отличать от HTTP-статуса и проверять форму полученных данных.
        var body = JSON.parse(xhr.responseText);
        if (xhr.status !== 200) throw new Error(body.error.message);
        if (body.a !== data.a || body.b !== data.b || body.operation !== data.operation || typeof body.value !== 'number' || !isFinite(body.value)) throw new Error('Неверный ответ сервера');
        done(null, body);
      } catch (error) { done(error); }
    };
    // Сбой/тайм-аут не доказывает, что сервер не выполнил мутацию: перед повтором нужно проверить
    // состояние.
    xhr.onerror = function () { done(new Error('Нет связи с сервером')); };
    xhr.ontimeout = function () { done(new Error('Сервер не ответил за 10 секунд')); };
    // Преобразуем объект в JSON-тело с ключами серверной схемы; Content-Type сообщает формат.
    xhr.send(JSON.stringify(data));
  }
  return {request: request};
}());
