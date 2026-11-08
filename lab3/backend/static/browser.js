// Вход и браузерный CRUD через XMLHttpRequest. DOM-обработчики отправляют JSON по относительному
// адресу API. Токен находится в памяти страницы; ES5 нужен старому браузеру телефона.
/* ES5-синтаксис и XMLHttpRequest для браузера Qt 5.6; JWT живёт только в памяти. */
(function () {
  'use strict';
  var token = '', busy = false;
  // Находим DOM по id. Значение должно совпадать с HTML, иначе получится null.
  function el(id) { return document.getElementById(id); }
  // Создаём случайный UUID для записи/операции; он не зависит от позиции строки и годится для повторов.
  function uuid() {
    var bytes = new Uint8Array(16);
    window.crypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    var hex = [];
    for (var i = 0; i < 16; i++) hex.push(('0' + bytes[i].toString(16)).slice(-2));
    return hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-' + hex.slice(6, 8).join('') + '-' + hex.slice(8, 10).join('') + '-' + hex.slice(10).join('');
  }
  // Общий HTTP-транспорт задаёт заголовки и обрабатывает ответ/сбой. busy защищает форму от
  // конкурирующих отправок.
  function request(method, path, data, version, callback) {
    // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
    if (busy) { el('status').textContent = 'Дождитесь завершения запроса'; return; }
    busy = true;
    // Асинхронный HTTP-клиент старого браузера. Ответ придёт в callback, не блокируя страницу.
    var xhr = new XMLHttpRequest();
    xhr.open(method, '/api/v1/' + path); xhr.timeout = 10000;
    xhr.setRequestHeader('Accept', 'application/json');
    // Передаём Bearer JWT после входа. Он хранится в памяти страницы и не включается в URL.
    if (token) xhr.setRequestHeader('Authorization', 'Bearer ' + token);
    if (data) xhr.setRequestHeader('Content-Type', 'application/json');
    if (method !== 'GET') xhr.setRequestHeader('Idempotency-Key', uuid());
    if (version) xhr.setRequestHeader('If-Match', '"' + version + '"');
    // onload означает получение ответа, даже HTTP-ошибки. Успех отдельно определяется диапазоном 2xx.
    xhr.onload = function () {
      busy = false;
      var body = null;
      // Разбираем ответ; ошибку JSON нужно отличать от HTTP-статуса и проверять форму полученных данных.
      try { body = xhr.responseText ? JSON.parse(xhr.responseText) : null; } catch (e) { /* Показываем исходный ответ ниже. */ }
      // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
      el('status').textContent = method + ' ' + path + '\nHTTP ' + xhr.status + '\n' + xhr.getAllResponseHeaders() + '\n' + xhr.responseText;
      if (xhr.status >= 200 && xhr.status < 300 && callback) callback(body);
    };
    // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
    xhr.onerror = xhr.ontimeout = function () { busy = false; el('status').textContent = 'Нет связи, ошибка TLS или тайм-аут. Обновите список перед повтором операции.'; };
    // Преобразуем объект в JSON-тело с ключами серверной схемы; Content-Type сообщает формат.
    xhr.send(data ? JSON.stringify(data) : null);
  }
  // Сбрасываем редактор и скрытые id/version, чтобы новая запись не перезаписала прежнюю.
  function clear() { el('expense').reset(); el('recordId').value = ''; el('version').value = ''; el('date').value = new Date().toISOString().slice(0, 10); }
  // Асинхронно читаем список, создаём DOM-строки и callbacks с id/version каждой записи.
  function refresh() {
    request('GET', 'expenses', null, null, function (rows) {
      // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
      el('list').textContent = '';
      rows.forEach(function (row) {
        // Создаём DOM узел записи. Кнопки замыкают id/version именно этой строки.
        var li = document.createElement('li');
        // Создаём DOM узел записи. Кнопки замыкают id/version именно этой строки.
        var text = document.createElement('div');
        // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
        text.textContent = row.date + ' · ' + row.category + ' · ' + (row.amount_minor / 100).toFixed(2) + ' руб. · ' + row.comment;
        li.appendChild(text);
        // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
        var edit = document.createElement('button'); edit.textContent = 'Изменить';
        edit.onclick = function () {
          el('recordId').value = row.id; el('version').value = row.version;
          el('date').value = row.date; el('category').value = row.category;
          el('amount').value = (row.amount_minor / 100).toFixed(2); el('comment').value = row.comment;
          el('expense').scrollIntoView();
        };
        // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
        var remove = document.createElement('button'); remove.textContent = 'Удалить';
        remove.onclick = function () { if (window.confirm('Удалить расход?')) request('DELETE', 'expenses/' + row.id, null, row.version, refresh); };
        li.appendChild(edit); li.appendChild(remove); el('list').appendChild(li);
      });
    });
  }
  el('login').onsubmit = function (event) {
    // Отменяем обычный переход формы: запрос отправляется JavaScript, обновляется только нужная область.
    event.preventDefault();
    request('POST', 'auth/login', {username: el('username').value, password: el('password').value}, null, function (body) {
      token = body.access_token; el('password').value = ''; refresh();
    });
  };
  el('expense').onsubmit = function (event) {
    // Отменяем обычный переход формы: запрос отправляется JavaScript, обновляется только нужная область.
    event.preventDefault();
    var value = el('amount').value.trim().replace(',', '.');
    // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
    if (!/^\d+(\.\d{1,2})?$/.test(value)) { el('status').textContent = 'Введите положительную сумму с точностью до копеек'; return; }
    var parts = value.split('.');
    var data = {date: el('date').value, category: el('category').value,
      amount_minor: Number(parts[0]) * 100 + Number(((parts[1] || '') + '00').slice(0, 2)), comment: el('comment').value};
    var id = el('recordId').value;
    if (!id) data.id = uuid();
    request(id ? 'PATCH' : 'POST', id ? 'expenses/' + id : 'expenses', data, el('version').value, function () { clear(); refresh(); });
  };
  // Вставляем обычный текст, а не HTML: строки пользователя/сервера не выполняются как разметка.
  el('logout').onclick = function () { token = ''; el('list').textContent = ''; clear(); el('status').textContent = 'Вы вышли'; };
  el('refresh').onclick = refresh; el('reset').onclick = clear; clear();
}());
