# Лабораторная №2 · вариант 1 · Список задач

Поля: заголовок `title` (1–160 символов), описание `description` (до 2000), статус `status` (`todo`, `doing`, `done`), срок `due_date` (YYYY-MM-DD). API — `/api/v1/tasks`, создание POST, изменение PATCH, чтение GET, удаление DELETE. JWT, права, ETag, версии и идемпотентность сохранены. UI, контроллер, транспорт и SQLite разделены.

Приложение «Задачи ЛР2», пакет `ru.kirik.taskslab2`. Оно устанавливается параллельно с ЛР3 и обоими клиентами расходов. Данные не мигрируют из других приложений.

## Зависимости и сертификат

```bash
cd ~/Unik/web_mobile_unik/kirik/lab2
python3 -m venv backend/.venv
backend/.venv/bin/python -m pip install -r backend/requirements.txt
```

Если сертификата нет, выполнить `bash certificates/generate.sh 192.168.0.104 192.168.0.118`. Уже существующие файлы не перезаписываются. При другом IP проверить SAN; после замены сертификата пересобрать клиент, а для ЛР3 обновить установленный TLS-конфиг nginx. Закрытый ключ остаётся только на сервере.

## Запуск

```bash
cd ~/Unik/web_mobile_unik/kirik/lab2/backend
.venv/bin/python run.py
```

Сервер работает, пока открыт терминал; остановка Ctrl+C. SQLite и JWT-ключ сохраняются в `backend/data/`.

На ПК и телефоне: **https://192.168.0.104:8543/**; документация `/docs`, `/openapi.json`. Вход `demo` / `demo12345`; `viewer` — чтение. Проверка: `curl --cacert certificates/server.crt https://192.168.0.104:8543/health`. Не отключать TLS-проверку через `-k`.

## Сборка, подпись и установка клиента

```bash
cd ~/Unik/web_mobile_unik/kirik/lab2
bash tools/build-client.sh
scp -O client/RPMS/ru.kirik.taskslab2-1.0.0-4.armv7hl.rpm defaultuser@192.168.2.16:/home/defaultuser/
ssh defaultuser@192.168.2.16 'sdk-deploy-rpm --silent --keepUserData /home/defaultuser/ru.kirik.taskslab2-1.0.0-4.armv7hl.rpm'
```

При смене Version/Release использовать имя из вывода сборщика. Пакет подписывается штатной ключевой парой Aurora SDK и проверяется. Скрипт использует PSDK `~/AuroraPlatformSDK/sdks/aurora_psdk`, target armv7hl; пути меняются через `LAB_PSDK`, `LAB_SDK`, `LAB_TARGET`. При запрете тихой установки убрать `--silent` и подтвердить на телефоне. `devel-su rpm -Uvh` не применять для пользовательского пакета.

В приложении указать `https://192.168.0.104:8543` и `/usr/share/ru.kirik.taskslab2/certificates/server.crt`. Новый элемент — «Новая задача», нажатие редактирует, долгое нажатие открывает меню удаления. Статус выбирается списком. Offline-переключатель приостанавливает сеть; очередь, JWT и кэш сохраняются между запусками. При конфликте доступны локальная и серверная версии.

## Проверки

```bash
cd ~/Unik/web_mobile_unik/kirik/lab2/backend
.venv/bin/python -m pytest -q
```

Для ЛР3 тестам нужны запущенные blue 9301/9302 и nginx 9543. Нативная проверка:

```bash
ssh defaultuser@192.168.2.16 'QT_LOGGING_TO_CONSOLE=1 /usr/bin/ru.kirik.taskslab2-tests https://192.168.0.104:8543 /usr/share/ru.kirik.taskslab2/certificates/server.crt'
```

[Полная демонстрация](DEMONSTRATION.md) · [Разбор архитектуры](EXPLANATION.md) · [Фактические результаты](docs/VALIDATION.md). Отчёты находятся в [../reports](../reports/); пересборка из `kirik`: `python3 tools/build_reports.py`. Листинги в отчётах — без комментариев.
