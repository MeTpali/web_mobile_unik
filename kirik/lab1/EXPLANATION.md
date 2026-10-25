# Калькулятор: устройство кода

Браузерный UI в public/app.js собирает два числа и операцию, показывает состояние и ошибки; асинхронный HTTP-сервис в public/api.js отправляет JSON через XMLHttpRequest. Чистая функция server/calculator.js выполняет вычисления и валидацию; Express-слой server/app.js отвечает за маршруты и HTTP-статусы. CSS содержит @media для узких экранов. Сервер не доверяет проверке формы.

Flutter-клиент разделён на models/calculation.dart, services/calculator_service.dart, controllers/calculator_controller.dart и ui/calculator_page.dart. Сервис отвечает за WebSocket/JSON и закрытие ресурсов, контроллер — за состояние, тайм-аут и соответствие request_id, UI — за виджеты. Python app/calculator.py вычисляет, protocol.py разбирает JSON, main.py обслуживает соединение. Ошибка деления на ноль не разрывает прикладной сеанс.

Операции используют обычные double, а не десятичную финансовую арифметику. Ограничение операндов ±10¹² не разрешает NaN/Infinity. История хранит 10 записей только в памяти. WebSocket/Flutter-код впоследствии проверен после разрешения пользователя; нативный сценарий с реальным сервером прошёл. Ограничения тестового runner приведены в docs/VALIDATION.md.
