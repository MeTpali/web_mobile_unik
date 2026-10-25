# Лабораторная №1 · вариант 1 · Калькулятор

Один проект лабораторной с двумя интерфейсами: браузер (`lab-01`) и нативный Flutter/WebSocket (`lab-02`). UI, состояние, транспорт и вычисления отделены друг от друга.

## Браузер

```bash
cd ~/Unik/web_mobile_unik/kirik/lab1/lab-01
npm ci
npm test
npm start
```

Node.js 24.13+ (ветка 24), Express; адрес ПК http://127.0.0.1:3100, телефона http://192.168.0.104:3100. Сборка Vite не требуется: сервер раздаёт `public/` с HTML, адаптивным CSS и ES5 JavaScript, включая асинхронный XMLHttpRequest. Это позволяет избежать зависимости от современного JS-движка браузера Авроры. POST `/api/calculate`: `{"a":12.5,"b":2,"operation":"/"}` → `{"a":12.5,"b":2,"operation":"/","value":6.25}`.

## WebSocket и Flutter

```bash
cd ~/Unik/web_mobile_unik/kirik/lab1/lab-02/backend
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python run.py
```

В другом терминале:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab1/lab-02/calculator
flutter-aurora pub get
flutter-aurora devices
flutter-aurora run -d <ID> --dart-define=WS_URL=ws://192.168.0.104:8100/ws/calculate
```

Зависимости Flutter установлены пользователем. Сборка, установка и нативный сценарий с настоящим WebSocket на телефоне прошли. Пакет платформы — ru.kirik.calculator, отдельный от исходного варианта №6. Для запуска уже настроенным SDK можно использовать полный путь `~/.local/opt/flutter_aurora_linux/bin/flutter` вместо оболочки `flutter-aurora`.

Операции +, -, *, /; отрицательные и дробные числа, запятая или точка в форме. Операнды ограничены ±10¹². Деление на ноль отклоняется сервером. Используется обычная арифметика double, поэтому десятичные дроби могут иметь стандартную погрешность представления. WebSocket сообщает ошибку в JSON и сохраняет соединение; request_id сопоставляет ответ, история — последние 10 вычислений в памяти.

[Подробная демонстрация](DEMONSTRATION.md) · [Разбор](EXPLANATION.md).

## Проверка на реальном устройстве

Результаты: [docs/VALIDATION.md](docs/VALIDATION.md), [JSON с телефона](docs/native-validation.json). Локальный Flutter test runner в SDK Авроры не содержит нужного patched SDK для Linux. Для нативной проверки предусмотрено:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab1/lab-02/calculator
flutter-aurora run --no-pub --no-resident -d <ID> -t integration/device_smoke.dart
```

Сначала запустить Python-сервер на 8100. Сценарий записывает результат в `~/.local/share/ru.kirik/calculator/verification.json` на телефоне. После проверки вернуть обычное приложение:

```bash
flutter-aurora run --no-pub --no-resident -d <ID> -t lib/main.dart
```

Сценарий выполняет настоящие запросы, проверяет ошибки и переподключение. Он не заменяет ручную проверку жестов/ввода и всех вариантов реального сетевого разрыва.
