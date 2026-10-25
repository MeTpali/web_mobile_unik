# Лабораторная №3 · вариант 6 · Учёт расходов

Пошаговый полный показ: [DEMONSTRATION.md](DEMONSTRATION.md).

FastAPI + PostgreSQL, два systemd-инстанса за nginx, HTTPS/WSS, blue-green и нативный клиент Qt/QML/C++ для Авроры 5.2.1.200. Вторая лабораторная в `lab2/` остаётся отдельной.

## Адреса и версии

| Компонент | Адрес / имя |
|---|---|
| nginx, единый адрес приложения | `https://192.168.0.118:9443` |
| Браузерная форма | `https://192.168.0.118:9443/` |
| Swagger / OpenAPI | `/docs`, `/openapi.json` |
| WebSocket | `wss://192.168.0.118:9443/api/v1/events` |
| blue | `127.0.0.1:9101`, `127.0.0.1:9102` |
| green | `127.0.0.1:9201`, `127.0.0.1:9202` |
| SSH телефона | `defaultuser@192.168.2.16` |
| Учебный вход | `demo` / `demo12345` |

IP ПК нужно проверять через `ip -4 addr`. Для телефона используется адрес ПК, а не адрес SSH телефона. Порт 8443 относится ко второй лабораторной.

## Первоначальная установка инфраструктуры

На Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y nginx postgresql python3-venv curl openssl
cd ~/Unik/web_mobile_unik/lab3
```

В рабочем экземпляре сертификат скопирован из второй лабораторной, включая SAN 192.168.0.118 и 192.168.0.104. В чистом клоне создать новый:

```bash
bash certificates/generate.sh 192.168.0.118 192.168.0.104
```

Существующие ключи скрипт не перезаписывает. При замене сертификата нужно обновить nginx и пакет клиента. Закрытый ключ не включается в Git и RPM.

Развернуть:

```bash
sudo bash deploy/scripts/install-host.sh
```

Скрипт создаёт пользователя `expenseslab`, БД `expenses_lab`, отдельное виртуальное окружение, systemd-шаблон и nginx-сайт на 9443. Секреты записываются в `/etc/expenses-lab/common.env`, а код — в `/opt/expenses-lab/releases/`. Исходный пользовательский репозиторий службы не используют и не изменяют.

Начальные снимки — blue 1.0.0 и green 2.0.0. Для текущего исходного кода подготовить новые снимки с поддержкой авторизации QML WebSocket:

```bash
sudo bash deploy/scripts/stage-release.sh blue 1.0.2
sudo bash deploy/scripts/stage-release.sh green 2.0.2
```

На текущем ПК они уже созданы. Повторно занимать существующий номер версии нельзя: опубликованные снимки не перезаписываются. При следующих изменениях использовать новый номер, например 1.0.3 и 2.0.3. `stage-release.sh` перезапускает процессы группы по одному; маршрутизацию nginx не переключает.

Во время запуска readiness-проверка может кратковременно сообщить `curl: (7)` до открытия порта. Итоговая строка «Группа … готова» означает, что проверки обоих процессов прошли.

## Обычный запуск и диагностика

```bash
sudo systemctl start expenses@blue-1 expenses@blue-2
systemctl status expenses@blue-1 expenses@blue-2 --no-pager
curl --cacert certificates/server.crt https://127.0.0.1:9443/ready
curl --cacert certificates/server.crt https://127.0.0.1:9443/meta
journalctl -u expenses@blue-1 -u expenses@blue-2 -f
```

Выбранная группа включена в автозапуск systemd. Падение процесса приводит к `Restart=on-failure`. Команда `systemctl stop` считается намеренной остановкой и не вызывает автоматического перезапуска.

`/health` показывает, что процесс жив; `/ready` проверяет PostgreSQL и готовность слушателя уведомлений. nginx использует пассивное исключение недоступных upstream; readiness проверяется скриптом до переключения версий. Это разные механизмы.

Заголовки `X-Backend-ID` и `X-App-Version` показывают обслуживший запрос процесс и версию. Лог nginx: `/var/log/nginx/expenses-lab.log`.

## Blue-green и откат

Переключить трафик на green:

```bash
sudo bash deploy/scripts/switch-release.sh green
curl --cacert certificates/server.crt https://127.0.0.1:9443/meta
```

Скрипт запускает оба green-инстанса, проверяет `/ready`, атомарно меняет upstream и выполняет `nginx -t` и reload. Старые процессы продолжают завершать запросы. После проверки остановить их:

```bash
sudo systemctl stop expenses@blue-1 expenses@blue-2
```

При закрытии старого WebSocket клиент переподключается и перечитывает данные через REST. Бесшовность REST и восстановление WebSocket проверяются отдельно.

Откат:

```bash
sudo bash deploy/scripts/switch-release.sh blue
sudo systemctl stop expenses@green-1 expenses@green-2
```

У green есть новая возможность `/api/v1/summary`: число расходов и общая сумма в копейках для текущего пользователя. Blue возвращает 404 для этого нового маршрута. Прежние CRUD-маршруты, JWT, версии записей, ETag и ключи идемпотентности совместимы; обе версии работают с одной схемой БД.

## Реальная демонстрация отказа и обновления

Автоматический сценарий с правами администратора:

```bash
sudo /opt/expenses-lab/venv/bin/python deploy/scripts/exercise-cluster.py
```

Он делает непрерывные авторизованные HTTPS-запросы, подключает WSS, останавливает именно тот blue-backend, который держит WebSocket, проверяет переподключение и push, переключается на green, останавливает blue, выполняет откат и возвращает трафик на blue. Создаёт и удаляет только собственные тестовые расходы. Результат — `docs/cluster-validation.json`.

Для ручной демонстрации в первом терминале запустить монитор:

```bash
backend/.venv/bin/python tools/monitor.py --seconds 180 --output docs/manual-monitor.json
```

Во втором терминале последовательно выполнить остановку одного инстанса, его запуск и переключения blue/green. Ручной монитор не меняет службы. При отказе backend nginx повторяет подходящие запросы на другом процессе. Повторы изменяющих операций после неопределённого исхода выполняет очередь клиента с прежним Idempotency-Key.

## Сборка, подпись и установка клиента

```bash
bash tools/build-client.sh
```

PSDK запускает rpmbuild через mb2. Скрипт `tools/sign_package.sh` выполняет этап подписи из задания через установленный в этом SDK штатный `rpmsign-external`, затем проверяет подпись. Обёртка явно называется `sign_package.sh`; отдельная SDK-команда с именем `sign_package` здесь не установлена.

Клиент имеет отдельный идентификатор `com.example.expenseslab3` и название «Расходы · ЛР3». Он устанавливается одновременно с «Расходы · ЛР2» (`com.example.expenseslab2`). У приложений отдельные настройки, JWT, SQLite и offline-очереди. Существующий пакет `com.example.expenses` и его данные сохраняются; новые клиенты начинают с чистыми настройками.

Номер Release указан в `client/rpm/com.example.expenseslab3.spec`; фактический путь готового пакета печатает сборщик:

```bash
scp -O client/RPMS/com.example.expenseslab3-2.0.0-8.armv7hl.rpm defaultuser@192.168.2.16:/home/defaultuser/
ssh defaultuser@192.168.2.16 \
  'sdk-deploy-rpm --silent --keepUserData /home/defaultuser/com.example.expenseslab3-2.0.0-8.armv7hl.rpm'
```

В приложении «Расходы · ЛР3» указать **https://192.168.0.118:9443**, затем войти. Адрес по умолчанию — 9443; настройки клиента ЛР2 не используются. Путь сертификата остаётся `/usr/share/com.example.expenseslab3/certificates/server.crt`.

Push реализован C++-сервисом с небольшим транспортным QML-адаптером штатного QtWebSockets. JWT передаётся первым защищённым WSS-кадром и не попадает в URL. При разрыве используются интервалы повторов 1, 2, 4, 8, 16, 30 секунд. Heartbeat контролирует зависшие соединения. После подключения клиент выполняет REST-синхронизацию; push не заменяет источник данных.

Для совместимости Qt 5.6 HTTP-запросы используют `Connection: close`. При сетевом сбое GET один раз повторяется через 250 мс после очистки соединений; мутации повторяются только через сохранённую очередь с прежним ключом.

В UI показаны состояние push, последний REST-backend и счётчик событий. Переключатель offline сохранён для демонстрации и приостанавливает обмен. Изменение из браузера под тем же пользователем должно обновить список телефона без ручного нажатия.

## Проверки

```bash
python3 -m venv backend/.venv
backend/.venv/bin/python -m pip install -r backend/requirements.txt
cd backend
.venv/bin/python -m pytest -q
```

Кластерные тесты ожидают работающую blue-группу на 9101/9102 и nginx на 9443. Они проверяют настоящие PostgreSQL, nginx и WSS, а не подставные сервисы.

Нативные тесты:

```bash
ssh defaultuser@192.168.2.16 \
  'QT_LOGGING_TO_CONSOLE=1 /usr/bin/com.example.expenseslab3-tests https://192.168.0.118:9443 /usr/share/com.example.expenseslab3/certificates/server.crt'
```

Снимки экрана исключены согласно политике устройства. Результаты проверок и ограничения фиксируются в `docs/VALIDATION.md`.

## Разбор и отчёт

- [Учебный разбор](EXPLANATION.md).
- [Результаты и сценарий защиты](docs/VALIDATION.md).
- [Отчёт DOCX](docs/REPORT.docx) и [Markdown](docs/REPORT.md). Листинги без комментариев, исходники с комментариями.

После изменения кода отчёт пересобирается командой `python3 tools/build_report.py`.

Нативный монитор для совместной демонстрации:

```bash
ssh defaultuser@192.168.2.16 \
  'QT_LOGGING_TO_CONSOLE=1 /usr/bin/com.example.expenseslab3-tests https://192.168.0.118:9443 /usr/share/com.example.expenseslab3/certificates/server.crt --watch'
```

После подключения монитора запустить `exercise-cluster.py` на ПК с sudo. Монитор ждёт сценарий до 10 минут и завершается после наблюдения green, возврата blue, push-событий и десяти успешных HTTP-запросов после восстановления. Он выводит отдельно количество успешных запросов, сетевых ошибок, подключений и событий. Временные сетевые ошибки учитываются; критерий телефона — восстановление работы и данных. Серверный монитор отдельно требует отсутствия HTTP-ошибок при отказе backend.
