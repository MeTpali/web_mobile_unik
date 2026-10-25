# Лабораторная №3 · вариант 1 · Список задач

Поля: заголовок `title` (1–160 символов), описание `description` (до 2000), статус `status` (`todo`, `doing`, `done`), срок `due_date` (YYYY-MM-DD). API — `/api/v1/tasks`, создание POST, изменение PATCH, чтение GET, удаление DELETE. JWT, права, ETag, версии и идемпотентность сохранены. UI, контроллер, транспорт и SQLite разделены.

Приложение «Задачи · ЛР3», пакет `ru.kirik.taskslab3`. Оно устанавливается параллельно с ЛР2 и обоими клиентами расходов. Данные не мигрируют из других приложений.

## Зависимости и сертификат

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
python3 -m venv backend/.venv
backend/.venv/bin/python -m pip install -r backend/requirements.txt
```

Если сертификата нет, выполнить `bash certificates/generate.sh 192.168.0.104 192.168.0.118`. Уже существующие файлы не перезаписываются. При другом IP проверить SAN; после замены сертификата пересобрать клиент, а для ЛР3 обновить установленный TLS-конфиг nginx. Закрытый ключ остаётся только на сервере.

## Запуск

Первое развёртывание на Ubuntu с установленными nginx и PostgreSQL:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
sudo bash deploy/scripts/install-host.sh
```

Создаются отдельные `/opt/kirik-tasks`, `/etc/kirik-tasks`, БД/роль `kirik_tasks`, пользователь `kiriktasks`, службы `kirik-tasks@blue-1/2`, nginx на 9543. Оригинальные службы расходов не затрагиваются. Начальные релизы blue 1.0.0 и green 2.0.0. Код лежит в неизменяемых снимках; после правок публиковать новый номер:

```bash
sudo bash deploy/scripts/stage-release.sh blue 1.0.1
sudo bash deploy/scripts/stage-release.sh green 2.0.1
```

Это пример следующих версий, не обязательная команда при каждом запуске. Занятый номер не перезаписывать. Переключение не требуется для публикации снимка; его выполняет отдельный скрипт. Обычный запуск:

```bash
sudo bash deploy/scripts/switch-release.sh blue
systemctl status kirik-tasks@blue-1 kirik-tasks@blue-2 --no-pager
curl --cacert certificates/server.crt https://127.0.0.1:9543/ready
```

Green добавляет `/api/v1/summary`: `count`, `done`, `open`. Blue возвращает 404 для этого нового маршрута. CRUD, JWT и схема PostgreSQL совместимы. WSS `/api/v1/events` отправляет `task.changed`; клиент после уведомления перечитывает REST. Повторы и heartbeat восстанавливают связь.

На ПК и телефоне: **https://192.168.0.104:9543/**; документация `/docs`, `/openapi.json`. Вход `demo` / `demo12345`; `viewer` — чтение. Проверка: `curl --cacert certificates/server.crt https://192.168.0.104:9543/ready`. Не отключать TLS-проверку через `-k`.

## Сборка, подпись и установка клиента

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
bash tools/build-client.sh
scp -O client/RPMS/ru.kirik.taskslab3-2.0.0-10.armv7hl.rpm defaultuser@192.168.2.16:/home/defaultuser/
ssh defaultuser@192.168.2.16 'sdk-deploy-rpm --silent --keepUserData /home/defaultuser/ru.kirik.taskslab3-2.0.0-10.armv7hl.rpm'
```

При смене Version/Release использовать имя из вывода сборщика. Пакет подписывается штатной ключевой парой Aurora SDK и проверяется. Скрипт использует PSDK `~/AuroraPlatformSDK/sdks/aurora_psdk`, target armv7hl; пути меняются через `LAB_PSDK`, `LAB_SDK`, `LAB_TARGET`. При запрете тихой установки убрать `--silent` и подтвердить на телефоне. `devel-su rpm -Uvh` не применять для пользовательского пакета.

В приложении указать `https://192.168.0.104:9543` и `/usr/share/ru.kirik.taskslab3/certificates/server.crt`. Новый элемент — «Новая задача», нажатие редактирует, долгое нажатие открывает меню удаления. Статус выбирается списком. Offline-переключатель приостанавливает сеть; очередь, JWT и кэш сохраняются между запусками. При конфликте доступны локальная и серверная версии.

## Проверки

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3/backend
.venv/bin/python -m pytest -q
```

Для ЛР3 тестам нужны запущенные blue 9301/9302 и nginx 9543. Нативная проверка:

```bash
ssh defaultuser@192.168.2.16 'QT_LOGGING_TO_CONSOLE=1 /usr/bin/ru.kirik.taskslab3-tests https://192.168.0.104:9543 /usr/share/ru.kirik.taskslab3/certificates/server.crt'
```

[Полная демонстрация](DEMONSTRATION.md) · [Разбор архитектуры](EXPLANATION.md) · [Фактические результаты](docs/VALIDATION.md). Отчёты находятся в [../reports](../reports/); пересборка из `kirik`: `python3 tools/build_reports.py`. Листинги в отчётах — без комментариев.

Автоматический отказ, green и откат:

```bash
sudo /opt/kirik-tasks/venv/bin/python deploy/scripts/exercise-cluster.py
```

Для совместной проверки сначала запустить телефонный `ru.kirik.taskslab3-tests` с теми же URL/сертификатом и дополнительным `--watch`, затем выполнить сценарий на ПК. Подробный порядок — в DEMONSTRATION.md. Только серверный PASS не доказывает восстановление телефона.
