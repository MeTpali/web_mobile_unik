// HTTP-транспорт или обработка действий пользователя. Импорты подключают зависимости; основной код
// выполняет одну роль в цепочке приложения.
/* UI и HTTP-сервис разделены: вычисления выполняет сервер. ES5 для старого браузера. */
(function () {
  'use strict';
  // Находим DOM по id. Значение должно совпадать с HTML, иначе получится null.
  function el(id) { return document.getElementById(id); }
  // Строго разбираем числовую строку, заменяем запятую и проверяем конечность/предел.
  function number(text) {
    var value = text.trim().replace(',', '.');
    if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value)) throw new Error('Введите два числа');
    var parsed = Number(value);
    if (!isFinite(parsed) || Math.abs(parsed) > 1e12) throw new Error('Операнды должны быть от −10¹² до 10¹²');
    return parsed;
  }
  el('calculator').onsubmit = function (event) {
    // Отменяем обычный переход формы: запрос отправляется JavaScript, обновляется только нужная область.
    event.preventDefault();
    if (el('submit').disabled) return;
    // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
    el('error').textContent = ''; el('result').textContent = '';
    var data;
    try { data = {a: number(el('a').value), b: number(el('b').value), operation: el('operation').value}; }
    // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
    catch (error) { el('error').textContent = error.message; return; }
    el('submit').disabled = true;
    CalculatorApi.request(data, function (error, body) {
      el('submit').disabled = false;
      // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
      if (error) el('error').textContent = error.message;
      // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
      else el('result').textContent = body.a + ' ' + body.operation + ' ' + body.b + ' = ' + body.value;
    });
  };
}());
