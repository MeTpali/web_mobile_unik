#!/usr/bin/env bash
# Установка служб, общей БД и nginx с отдельными секретами. Сценарий работает на компьютере, не
# телефоне. Blue/green — группы версий; готовность проверяется до переключения. Данные и секреты не
# должны сбрасываться при обновлении кода.
# Запускается пользователем через sudo. Изменения ограничены лабораторными службами.
# Строгий Bash: -e прерывает необработанную ошибку, -u запрещает неопределённую переменную, pipefail
# учитывает сбой внутри конвейера.
set -euo pipefail
# Проверяем root до изменения системных файлов. GUI телефона не требует таких прав.
[[ $EUID -eq 0 ]] || { echo 'Запустите: sudo bash deploy/scripts/install-host.sh'; exit 1; }
# Находим корень относительно файла скрипта, а не произвольного текущего каталога запуска.
lab_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
for lab_tool in nginx psql python3 openssl; do command -v "$lab_tool" >/dev/null; done
[[ -f "$lab_root/certificates/server.crt" && -f "$lab_root/certificates/server.key" ]] || {
    echo 'Сначала создайте certificates/server.crt и server.key по README.'; exit 1;
}
id expenseslab >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/expenses-lab --shell /usr/sbin/nologin expenseslab
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -d -m 755 /opt/expenses-lab/releases /opt/expenses-lab/instances /etc/nginx/expenses-lab
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -d -m 750 -o root -g expenseslab /etc/expenses-lab
if [[ ! -f /etc/expenses-lab/common.env ]]; then
    lab_db_password=$(openssl rand -hex 24)
    lab_jwt_secret=$(openssl rand -hex 32)
    # Секреты не печатаются и не попадают в Git.
    # Записываем общий DSN и JWT-секрет в отдельный защищённый env. Это постоянные параметры: повторная
    # генерация сломала бы действующие сессии/доступ БД.
    printf 'DATABASE_URL=postgresql://expenses_lab:%s@127.0.0.1:5432/expenses_lab\nJWT_SECRET=%s\n' \
        "$lab_db_password" "$lab_jwt_secret" > /etc/expenses-lab/common.env
    chown root:expenseslab /etc/expenses-lab/common.env
    chmod 640 /etc/expenses-lab/common.env
    # Далее heredoc передаёт SQL в psql под системным postgres. Сначала создаётся роль, затем БД при их
    # отсутствии; %L безопасно экранирует пароль, а gexec исполняет сгенерированную команду.
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -v lab_password="$lab_db_password" <<'SQL'
SELECT format('CREATE ROLE expenses_lab LOGIN PASSWORD %L', :'lab_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='expenses_lab') \gexec
SELECT 'CREATE DATABASE expenses_lab OWNER expenses_lab'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='expenses_lab') \gexec
SQL
fi
# Изолируем Python-зависимости сервера от системных библиотек Ubuntu.
python3 -m venv /opt/expenses-lab/venv
# Устанавливаем зафиксированные версии в venv; может потребоваться доступ к репозиторию пакетов.
/opt/expenses-lab/venv/bin/python -m pip install -r "$lab_root/backend/requirements.txt"
for lab_release in 1.0.0 2.0.0; do
    lab_dir="/opt/expenses-lab/releases/$lab_release"
    if [[ ! -d "$lab_dir" ]]; then
        # Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
        install -d "$lab_dir/backend"
        # Копируем app/static в новый снимок релиза. Изменения исходников после копирования не изменят уже
        # опубликованную версию.
        cp -r "$lab_root/backend/app" "$lab_root/backend/static" "$lab_dir/backend/"
        if [[ $lab_release == 1.0.0 ]]; then lab_features='[]'; else lab_features='["summary"]'; fi
        # release.json фиксирует версию и включённые возможности снимка. Backend читает его при запуске, а не
        # получает версию из названия GUI.
        printf '{"version":"%s","features":%s}\n' "$lab_release" "$lab_features" > "$lab_dir/backend/app/release.json"
    fi
done
# Immutable releases: повторный запуск не переписывает код уже работающей версии.
for lab_color in blue green; do
    if [[ $lab_color == blue ]]; then lab_version=1.0.0; lab_port=9100; else lab_version=2.0.0; lab_port=9200; fi
    for lab_number in 1 2; do
        lab_name="$lab_color-$lab_number"
        # Ссылка выбирает релиз или конфигурацию без переписывания опубликованного содержимого.
        ln -sfn "/opt/expenses-lab/releases/$lab_version" "/opt/expenses-lab/instances/$lab_name"
        printf 'PORT=%s\n' "$((lab_port + lab_number))" > "/etc/expenses-lab/$lab_name.env"
    done
done
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 600 "$lab_root/certificates/server.key" /etc/expenses-lab/server.key
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/certificates/server.crt" /etc/expenses-lab/server.crt
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/deploy/systemd/expenses@.service" /etc/systemd/system/expenses@.service
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/deploy/nginx/blue.conf" /etc/nginx/expenses-lab/blue.conf
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/deploy/nginx/green.conf" /etc/nginx/expenses-lab/green.conf
[[ -L /etc/nginx/expenses-lab/active.conf ]] || ln -s blue.conf /etc/nginx/expenses-lab/active.conf
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/deploy/nginx/expenses.conf" /etc/nginx/sites-available/expenses-lab.conf
# Ссылка выбирает релиз или конфигурацию без переписывания опубликованного содержимого.
ln -sfn /etc/nginx/sites-available/expenses-lab.conf /etc/nginx/sites-enabled/expenses-lab.conf
# Перечитываем unit-файлы systemd. Сама команда не перезапускает уже работающий backend.
systemctl daemon-reload
# Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
systemctl enable --now expenses@blue-1 expenses@blue-2
for lab_port in 9101 9102; do
    lab_ready=false
    for lab_attempt in {1..30}; do
        # Готовность /ready проверяется с тайм-аутом и ограниченным числом попыток. Открытый порт ещё не
        # означает доступную БД.
        if curl -fsS --max-time 2 "http://127.0.0.1:$lab_port/ready" >/dev/null; then lab_ready=true; break; fi
        # Пауза между ограниченными проверками. Готовность определяется следующим запросом, а не только
        # истечением времени.
        sleep 1
    done
    $lab_ready || { echo "Инстанс на $lab_port не готов: journalctl -u expenses@blue-1 -u expenses@blue-2"; exit 1; }
done
# Проверяем синтаксис перед reload: неверная конфигурация не должна становиться активной.
nginx -t
# Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
systemctl enable nginx postgresql
# Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
systemctl reload nginx
echo 'Готово: два blue backend, nginx HTTPS :9443, общая PostgreSQL.'
