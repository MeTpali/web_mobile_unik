/* HTTP-сервис не зависит от DOM: получает JSON и возвращает результат через callback. */
var CalculatorApi = (function () {
  'use strict';
  // Асинхронный XMLHttpRequest не блокирует интерфейс во время ожидания сети.
  function request(data, done) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/calculate'); xhr.timeout = 10000;
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.onload = function () {
      try {
        var body = JSON.parse(xhr.responseText);
        if (xhr.status !== 200) throw new Error(body.error.message);
        if (body.a !== data.a || body.b !== data.b || body.operation !== data.operation || typeof body.value !== 'number' || !isFinite(body.value)) throw new Error('Неверный ответ сервера');
        done(null, body);
      } catch (error) { done(error); }
    };
    xhr.onerror = function () { done(new Error('Нет связи с сервером')); };
    xhr.ontimeout = function () { done(new Error('Сервер не ответил за 10 секунд')); };
    xhr.send(JSON.stringify(data));
  }
  return {request: request};
}());
