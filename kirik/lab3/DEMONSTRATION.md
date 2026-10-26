# Полная демонстрация лабораторной №3

Вариант №1 — задачи. Показываем упаковку и подпись клиента, PostgreSQL, systemd, nginx, балансировку, WSS-push, отказ одного backend, blue-green и откат. Приложение на телефоне — **«Задачи ЛР3»** (`ru.kirik.taskslab3`). Оно независимо от клиента ЛР2.

## 1. Проверить подготовленную инфраструктуру

На текущем ПК инфраструктура уже развёрнута. Не запускать установщик перед каждым показом и не пересоздавать существующие релизы.

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
ip -4 addr
ssh -o ConnectTimeout=8 defaultuser@192.168.2.16 'echo SSH_OK'
openssl x509 -in certificates/server.crt -noout -dates -ext subjectAltName
systemctl is-active nginx postgresql
systemctl list-units 'kirik-tasks@*' --all --no-pager
sudo ls /etc/kirik-tasks /opt/kirik-tasks/releases
```

Примеры используют последний проверенный IP ПК `192.168.0.104`, который присутствует в SAN сертификата. Если IP изменился, заменить его в URL и проверить сертификат. Телефон должен иметь сетевой маршрут к ПК; доступ по USB/SSH не подтверждает доступность HTTPS по Wi-Fi.

Ожидаемая схема:

| Компонент | Назначение |
|---|---|
| `https://192.168.0.104:9543` | Единый адрес nginx для браузера и приложения |
| `wss://192.168.0.104:9543/api/v1/events` | Push-канал; клиент выводит адрес из HTTPS URL |
| `kirik-tasks@blue-1`, `kirik-tasks@blue-2` | Версия 1.0.0, HTTP на 127.0.0.1:9301/9302 |
| `kirik-tasks@green-1`, `kirik-tasks@green-2` | Версия 2.0.0, HTTP на 127.0.0.1:9401/9402 |
| PostgreSQL `kirik_tasks` | Общие задачи, версии, идемпотентность и события |
| `defaultuser@192.168.2.16` | SSH телефона; не адрес API |

Для первого развёртывания на неподготовленном ПК выполнить раздел «Первоначальная установка инфраструктуры» в [README.md](README.md). Установщик: `sudo bash deploy/scripts/install-host.sh`. Затем подготовить blue/green через `stage-release.sh` с ещё не занятыми номерами версий. Если 1.0.0/2.0.0 уже существуют, их повторно не публиковать. При изменении сертификата нужно обновить и nginx, и публичный сертификат в RPM; одного изменения URL недостаточно.

## 2. Привести кластер к исходному состоянию blue

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
sudo systemctl start postgresql nginx
sudo bash deploy/scripts/switch-release.sh blue
sudo systemctl stop kirik-tasks@green-1 kirik-tasks@green-2
systemctl status kirik-tasks@blue-1 kirik-tasks@blue-2 --no-pager
systemctl is-enabled kirik-tasks@blue-1 kirik-tasks@blue-2
curl --cacert certificates/server.crt https://127.0.0.1:9543/ready
curl --cacert certificates/server.crt https://127.0.0.1:9543/meta
```

Ожидается: два blue-процесса active/running и enabled; `/ready` возвращает успешный ответ, `/meta` показывает blue и 1.0.0. Скрипт переключения запускает новую группу и проверяет её готовность до изменения nginx. Если шаг завершился ошибкой, сначала устранить её, затем продолжать.

`/health` означает, что процесс жив. `/ready` дополнительно проверяет подключение к БД и готовность слушателя событий. nginx исключает недоступные upstream пассивно; это не периодический опрос `/ready`.

## 3. Показать systemd, nginx и PostgreSQL

```bash
systemctl cat kirik-tasks@blue-1
systemctl show kirik-tasks@blue-1 -p MainPID -p Restart -p FragmentPath
systemctl show kirik-tasks@blue-2 -p MainPID -p Restart -p FragmentPath
sudo nginx -t
sudo readlink /etc/nginx/kirik-tasks/active.conf
sudo sed -n '1,180p' /etc/nginx/sites-enabled/kirik-tasks.conf
sudo -u postgres psql -d kirik_tasks -c '\dt'
```

Основной конфиг проекта — `deploy/nginx/kirik-tasks.conf`; установщик создаёт ссылку `sites-enabled/kirik-tasks.conf`. Не выводить `common.env` с паролем БД и JWT-ключом.

Объяснить:

- systemd-шаблон запускает независимые backend-процессы, выбранная группа включена в автозапуск;
- nginx завершает TLS, проксирует HTTP и WebSocket и распределяет запросы;
- процессы используют одну PostgreSQL и общий JWT-ключ, поэтому запросы одного пользователя могут попадать на разные backend;
- PostgreSQL LISTEN/NOTIFY передаёт события между процессами после фиксации изменений;
- `Restart=on-failure` помогает при падении процесса, но намеренный `systemctl stop` сам его не перезапускает.

Показать исходники `deploy/systemd/kirik-tasks@.service`, `deploy/nginx/kirik-tasks.conf`, `backend/app/storage.py` и `backend/app/push.py`. Для объяснения проекта не требуется показывать секреты или менять общую БД.

## 4. Показать сборку, подпись и установку RPM

Отдельный клиент уже установлен на телефон. При необходимости продемонстрировать воспроизводимую сборку:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
bash tools/build-client.sh
```

Ожидается сборка через mb2/rpmbuild, затем подпись и `Signatures successfully verified`. В журнале `client/build.log` видны этапы сборки. Обёртка `tools/sign_package.sh` использует штатный `rpmsign-external`: это установленный механизм подписи в данном SDK.

Для отдельного показа проверки готового RPM:

```bash
~/AuroraPlatformSDK/sdks/aurora_psdk/sdk-chroot rpmsign-external verify \
  ~/Unik/web_mobile_unik/kirik/lab3/client/RPMS/ru.kirik.taskslab3-2.0.0-11.armv7hl.rpm
```

Установка:

```bash
scp -O client/RPMS/ru.kirik.taskslab3-2.0.0-11.armv7hl.rpm defaultuser@192.168.2.16:/home/defaultuser/
ssh defaultuser@192.168.2.16 \
  'sdk-deploy-rpm --silent --keepUserData /home/defaultuser/ru.kirik.taskslab3-2.0.0-11.armv7hl.rpm'
```

Если версия/Release изменились, использовать имя из вывода сборщика. Ожидается `Installation successful`. При запрете тихой установки убрать `--silent` и подтвердить установку на телефоне. Не использовать `devel-su rpm -Uvh` для обычного приложения: ранее политика отвергала пакет как несистемный.

Показать два значка: «Задачи · ЛР2» и «Задачи ЛР3». RPM клиента имеет версию 2.0.0, а версии backend — 1.0.0/2.0.0: это разные независимо версионируемые компоненты. Blue-green ниже обновляет сервер, не переустанавливая телефон.

## 5. Подключить телефон и показать WSS-push

Открыть **«Задачи ЛР3»**:

| Поле | Значение |
|---|---|
| Сервер | `https://192.168.0.104:9543` |
| Пользователь / пароль | `demo` / `demo12345` |
| Сертификат | `/usr/share/ru.kirik.taskslab3/certificates/server.crt` |

Выключить offline, войти, дождаться синхронизации и подключения push. Сервер задаётся через `https://`, WSS-сервис настраивается автоматически. Не вводить порт ЛР2 8543.

В браузере ПК открыть `https://192.168.0.104:9543/`, войти под тем же `demo`:

1. Создать задачу `Демо ЛР3 push`.
2. Без нажатия «Синхронизировать» на телефоне дождаться появления записи, изменения счётчика событий и текста последнего события.
3. Изменить статус в браузере: телефон должен обновиться автоматически.
4. Удалить запись в браузере: телефон должен убрать её из списка.
5. Показать системное уведомление Авроры: «Задача добавлена», «Задача изменена», «Задача удалена». Изменения заменяют одну запись. Баннер зависит от настроек ОС; также проверить шторку.
6. Приложение должно оставаться запущенным и online. После полного завершения процесса получение не предусмотрено.

Показать в UI последний REST-backend и состояние push. Backend, отправивший событие, и backend WebSocket-соединения могут различаться: события передаются между процессами через БД. Для доказательства push важно изменение счётчика/события, а не только появление записи спустя 30 секунд: у клиента есть и периодическая синхронизация.

Показать `client/src/pushservice.cpp`, `client/services/PushSocket.qml`, `client/src/taskcontroller.cpp`: JWT передаётся первым защищённым WSS-кадром, при событии запрашивается актуальный REST-снимок, после разрыва выполняются повторы и восстановление. Push не заменяет хранение данных и не гарантирует доставку каждого события при отключении.

## 6. Показать балансировку

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
for lab_attempt in {1..10}; do
  curl -fsS --cacert certificates/server.crt https://127.0.0.1:9543/meta
  echo
done
curl -sS -D - --cacert certificates/server.crt https://127.0.0.1:9543/meta -o /dev/null
```

В ответах должны встретиться `blue-1` и `blue-2`, в заголовках — `X-Backend-ID` и `X-App-Version`. Не требовать строгого чередования: на распределение влияют другие запросы и состояние upstream. Если виден один backend, проверить готовность обоих и повторить серию.

## 7. Запустить непрерывный монитор для ручного показа

Подготовить Python-окружение один раз, если `backend/.venv` ещё нет:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
python3 -m venv backend/.venv
backend/.venv/bin/python -m pip install -r backend/requirements.txt
```

Терминал A:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
backend/.venv/bin/python tools/monitor.py --seconds 600 --output docs/manual-monitor.json
```

Оставить работать до завершения отказа, green и отката. Он выводит HTTP-статусы и backend, ничего не переключает. Если завершился раньше показа, запустить заново. Ctrl+C выводит и сохраняет результат. Целевой итог контролируемого отказа — непустой список успешных запросов и `failures: []`; обнаруженную ошибку фиксировать, а не скрывать.

## 8. Вручную отключить один backend

Терминал B, пока монитор A работает:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
sudo systemctl stop kirik-tasks@blue-1
systemctl is-active kirik-tasks@blue-1 kirik-tasks@blue-2
curl --cacert certificates/server.crt https://127.0.0.1:9543/meta
```

Ожидается blue-1 inactive, blue-2 active; запросы через nginx продолжаются. На телефоне создать/изменить демонстрационный задачу и убедиться, что очередь отправилась. В браузере изменить его и проверить получение push телефоном.

Если WSS держал blue-1, должно произойти переподключение к blue-2. Если WSS изначально был на blue-2, его разрыва от этой остановки не будет — это ожидаемо. Автоматический сценарий ниже выбирает именно backend своего WebSocket.

Восстановить первый backend **до следующего шага**:

```bash
sudo systemctl start kirik-tasks@blue-1
curl -f http://127.0.0.1:9301/ready
```

Если порт ещё не открылся, подождать несколько секунд и повторить `/ready`. Не отключать оба экземпляра одновременно ради демонстрации отказоустойчивости.

## 9. Показать blue-green без смены адреса клиента

Монитор A продолжает работать. Терминал B:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
sudo bash deploy/scripts/switch-release.sh green
curl --cacert certificates/server.crt https://127.0.0.1:9543/meta
```

Дождаться успешного завершения скрипта. Новые HTTP-запросы должны обслуживать green 2.0.0. Старое WSS-соединение может оставаться на blue после reload — это нормальное завершение старых соединений nginx.

После проверки green остановить старую группу:

```bash
sudo systemctl stop kirik-tasks@blue-1 kirik-tasks@blue-2
```

На телефоне дождаться восстановления WSS на green; создать запись и проверить обратный push из браузера. URL остаётся `https://192.168.0.104:9543`, повторный вход обычно не требуется: JWT и БД общие.

Для показа новой функции green получить JWT в терминале B и вызвать summary:

```bash
LAB3_TOKEN=$(curl -fsS --cacert certificates/server.crt https://127.0.0.1:9543/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo12345"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
curl -i --cacert certificates/server.crt https://127.0.0.1:9543/api/v1/summary \
  -H "Authorization: Bearer $LAB3_TOKEN"
```

Ожидается 200, число всех, завершённых и открытых задач. Новая возможность относится к серверу; UI телефона переустанавливать не нужно.

## 10. Выполнить откат

```bash
sudo bash deploy/scripts/switch-release.sh blue
curl --cacert certificates/server.crt https://127.0.0.1:9543/meta
sudo systemctl stop kirik-tasks@green-1 kirik-tasks@green-2
curl -i --cacert certificates/server.crt https://127.0.0.1:9543/api/v1/summary \
  -H "Authorization: Bearer $LAB3_TOKEN"
```

Ожидается blue 1.0.0; summary вернёт 404, обычный CRUD продолжит работать с теми же данными. WSS телефона восстановится на blue. Создать/изменить тестовую запись и ещё раз показать push.

Теперь завершить монитор A через Ctrl+C и показать `docs/manual-monitor.json`: должны присутствовать backend обеих версий. Отсутствие ошибок относится только к измеренному интервалу; восстановление WebSocket оценивается отдельно от непрерывности HTTP.

## 11. Автоматическая проверка сервера совместно с телефоном

Этот сценарий можно использовать вместо ручных переключений либо как подтверждение после них. Он реально останавливает backend и меняет активную группу; запускать последовательно, не одновременно с ручными переключениями.

Сначала терминал C — монитор телефона:

```bash
ssh defaultuser@192.168.2.16 \
  'QT_LOGGING_TO_CONSOLE=1 /usr/bin/ru.kirik.taskslab3-tests https://192.168.0.104:9543 /usr/share/ru.kirik.taskslab3/certificates/server.crt --watch'
```

Дождаться вывода о подключении WSS/первых успешных запросах. Монитор ждёт сценарий до 10 минут. Затем **сразу** терминал B:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
sudo /opt/kirik-tasks/venv/bin/python deploy/scripts/exercise-cluster.py
```

Дождаться завершения обоих терминалов. Скрипт создаёт свои тестовые задачи, поддерживает HTTPS-нагрузку, отключает backend своего WSS, проверяет push, выполняет green и откат. Итоги записываются в `docs/cluster-validation.json`; новый запуск заменяет предыдущий результат.

Ожидаемый итог сервера:

```text
PASS: failover, push reconnect, blue-green, rollback, no HTTP downtime
```

В JSON — ненулевое число запросов, обе версии backend, `failures: []`, WSS-подключения и push-события. Числа запросов не обязаны совпадать с прошлым запуском.

Ожидаемый итог телефона:

```text
WATCH RESULT ...
PASS native phone: failover, blue-green reconnect, push notifications
```

Телефон завершает проверку после наблюдения green, возврата blue, push и успешных HTTP-запросов после восстановления. Его счётчик временных сетевых ошибок выводится отдельно: проверка восстановления телефона и проверка отсутствия HTTP-простоя серверного монитора — разные критерии. Серверный PASS без телефонного результата не доказывает успешное переподключение именно Qt-клиента.

## 12. Показать интеграционные тесты

Вернуть blue и не выполнять параллельных переключений:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
sudo bash deploy/scripts/switch-release.sh blue
cd backend
.venv/bin/python -m pytest -q
```

Ожидается 5 успешных интеграционных тестов: балансировка, общий JWT, идемпотентность, конфликты параллельных правок, межпроцессный push и изоляция пользователей. Тесты работают с настоящими nginx/PostgreSQL; backend 9301/9302 должны быть запущены.

Обычные нативные тесты отдельного клиента:

```bash
ssh defaultuser@192.168.2.16 \
  'QT_LOGGING_TO_CONSOLE=1 /usr/bin/ru.kirik.taskslab3-tests https://192.168.0.104:9543 /usr/share/ru.kirik.taskslab3/certificates/server.crt'
```

Ожидаются `PASS SQLite`, `PASS WSS native` и `PASS HTTPS native`. Тестовые программы используют временные локальные данные и собственные серверные записи. Offline-кэш и очередь клиента ЛР3 можно дополнительно показать по сценарию ЛР2, используя его собственный сервер 9543.

## 13. Диагностика и завершение

```bash
systemctl status kirik-tasks@blue-1 kirik-tasks@blue-2 --no-pager
journalctl -u kirik-tasks@blue-1 -u kirik-tasks@blue-2 -n 60 --no-pager
sudo tail -n 40 /var/log/nginx/kirik-tasks.log
```

| Проблема | Проверка |
|---|---|
| nginx возвращает 502 | Активная группа, её systemd-процессы, локальные `/ready`, доступность PostgreSQL |
| Readiness не прошёл | Журнал backend и БД; не обходить проверку принудительным изменением upstream |
| REST работает, push нет | Выключен ли offline, одинаковые аккаунты, WSS-статус, заголовки Upgrade в nginx, установлен ли актуальный клиент |
| Нет переподключения после reload | Старое соединение ещё живо: после проверки новой группы остановить старую |
| Таймаут на телефоне | Проверить текущий IP, порт 9543, маршрут к ПК и сертификат; не подставлять SSH-адрес телефона |
| `curl: (7)` при запуске процесса | Кратковременная ошибка допустима до открытия порта; важен итог readiness и код завершения скрипта |
| `stage-release.sh` отклоняет версию | Уже опубликованный номер не перезаписывается; для нового кода использовать новый номер |
| Монитор телефона истёк | Сначала вернуть blue, затем запустить монитор заново и сразу сценарий на ПК |

После показа восстановить исходное состояние:

```bash
cd ~/Unik/web_mobile_unik/kirik/lab3
sudo bash deploy/scripts/switch-release.sh blue
sudo systemctl stop kirik-tasks@green-1 kirik-tasks@green-2
curl --cacert certificates/server.crt https://127.0.0.1:9543/ready
```

Удалить только свои записи `Демо ЛР3`, синхронизировать телефон, завершить мониторы. nginx/PostgreSQL и blue можно оставить работать: они настроены как службы. Не останавливать общие службы ради завершения показа и не менять сервер ЛР2 на 8543.

Показ считается полным, когда продемонстрированы подпись и установка RPM, два backend и общая БД, балансировка, WSS-события, реальный отказ процесса, работа клиента после отказа, green с новой функцией и откат с сохранением данных. Живой показ телефона и журналы используются без запрещённых снимков экрана.


## Новая компоновка клиента

Главный экран — «Мой план»: счётчики этапов, фильтр статуса и карточки задач. Внизу находятся «Настройки», «Обновить» и «+ Задача». Вход, адрес сервера, сертификат, offline и диагностика находятся на отдельной странице «Настройки» → «Подключение». При конфликте на главном экране появляется кнопка «Разобрать конфликт»; выбор серверной или локальной версии доступен на странице подключения.

Создание и редактирование разбиты на блоки «Что нужно сделать», «Срок и этап», «Подробности». На карточке явно доступны изменение и удаление с возможностью отмены. Веб-страница использует рабочую доску со списком и боковыми блоками учётной записи, редактора и состояния запроса. Для появления новой веб-страницы ЛР3 в работающем кластере нужен отдельный выпуск через stage-release.sh; уже установленный релиз сам не изменяется.
