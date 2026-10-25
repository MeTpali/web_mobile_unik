/* UI и HTTP-сервис разделены: вычисления выполняет сервер. ES5 для старого браузера. */
(function () {
  'use strict';
  function el(id) { return document.getElementById(id); }
  function number(text) {
    var value = text.trim().replace(',', '.');
    if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value)) throw new Error('Введите два числа');
    var parsed = Number(value);
    if (!isFinite(parsed) || Math.abs(parsed) > 1e12) throw new Error('Операнды должны быть от −10¹² до 10¹²');
    return parsed;
  }
  el('calculator').onsubmit = function (event) {
    event.preventDefault();
    if (el('submit').disabled) return;
    el('error').textContent = ''; el('result').textContent = '';
    var data;
    try { data = {a: number(el('a').value), b: number(el('b').value), operation: el('operation').value}; }
    catch (error) { el('error').textContent = error.message; return; }
    el('submit').disabled = true;
    CalculatorApi.request(data, function (error, body) {
      el('submit').disabled = false;
      if (error) el('error').textContent = error.message;
      else el('result').textContent = body.a + ' ' + body.operation + ' ' + body.b + ' = ' + body.value;
    });
  };
}());
