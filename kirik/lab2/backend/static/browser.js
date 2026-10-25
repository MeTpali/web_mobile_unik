/* ES5-синтаксис и XMLHttpRequest для браузера Qt 5.6; JWT живёт только в памяти. */
(function () {
  'use strict';
  var token = '', busy = false;
  function el(id) { return document.getElementById(id); }
  function uuid() {
    var bytes = new Uint8Array(16);
    window.crypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    var hex = [];
    for (var i = 0; i < 16; i++) hex.push(('0' + bytes[i].toString(16)).slice(-2));
    return hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-' + hex.slice(6, 8).join('') + '-' + hex.slice(8, 10).join('') + '-' + hex.slice(10).join('');
  }
  function request(method, path, data, version, callback) {
    if (busy) { el('status').textContent = 'Дождитесь завершения запроса'; return; }
    busy = true;
    var xhr = new XMLHttpRequest();
    xhr.open(method, '/api/v1/' + path); xhr.timeout = 10000;
    xhr.setRequestHeader('Accept', 'application/json');
    if (token) xhr.setRequestHeader('Authorization', 'Bearer ' + token);
    if (data) xhr.setRequestHeader('Content-Type', 'application/json');
    if (method !== 'GET') xhr.setRequestHeader('Idempotency-Key', uuid());
    if (version) xhr.setRequestHeader('If-Match', '"' + version + '"');
    xhr.onload = function () {
      busy = false;
      var body = null;
      try { body = xhr.responseText ? JSON.parse(xhr.responseText) : null; } catch (e) { /* Показываем исходный ответ ниже. */ }
      el('status').textContent = method + ' ' + path + '\nHTTP ' + xhr.status + '\n' + xhr.getAllResponseHeaders() + '\n' + xhr.responseText;
      if (xhr.status >= 200 && xhr.status < 300 && callback) callback(body);
    };
    xhr.onerror = xhr.ontimeout = function () { busy = false; el('status').textContent = 'Нет связи, ошибка TLS или тайм-аут. Обновите список перед повтором операции.'; };
    xhr.send(data ? JSON.stringify(data) : null);
  }
  function clear() { el('task').reset(); el('recordId').value = ''; el('version').value = ''; el('due_date').value = new Date().toISOString().slice(0, 10); }
  function refresh() {
    request('GET', 'tasks', null, null, function (rows) {
      el('list').textContent = '';
      rows.forEach(function (row) {
        var li = document.createElement('li');
        var text = document.createElement('div');
        text.textContent = row.due_date + ' · ' + row.title + ' · ' + row.status + ' · ' + row.description;
        li.appendChild(text);
        var edit = document.createElement('button'); edit.textContent = 'Изменить';
        edit.onclick = function () {
          el('recordId').value = row.id; el('version').value = row.version;
          el('due_date').value = row.due_date; el('title').value = row.title;
          el('state').value = row.status; el('description').value = row.description;
          el('task').scrollIntoView();
        };
        var remove = document.createElement('button'); remove.textContent = 'Удалить';
        remove.onclick = function () { if (window.confirm('Удалить задачу?')) request('DELETE', 'tasks/' + row.id, null, row.version, refresh); };
        li.appendChild(edit); li.appendChild(remove); el('list').appendChild(li);
      });
    });
  }
  el('login').onsubmit = function (event) {
    event.preventDefault();
    request('POST', 'auth/login', {username: el('username').value, password: el('password').value}, null, function (body) {
      token = body.access_token; el('password').value = ''; refresh();
    });
  };
  el('task').onsubmit = function (event) {
    event.preventDefault();
    var data = {due_date: el('due_date').value, title: el('title').value,
      status: el('state').value, description: el('description').value};
    var id = el('recordId').value;
    if (!id) data.id = uuid();
    request(id ? 'PATCH' : 'POST', id ? 'tasks/' + id : 'tasks', data, el('version').value, function () { clear(); refresh(); });
  };
  el('logout').onclick = function () { token = ''; el('list').textContent = ''; clear(); el('status').textContent = 'Вы вышли'; };
  el('refresh').onclick = refresh; el('reset').onclick = clear; clear();
}());
