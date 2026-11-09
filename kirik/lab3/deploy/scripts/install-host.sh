#!/usr/bin/env bash
# Развёртывание изолированных БД, systemd и nginx. Сценарий работает на компьютере, не телефоне.
# Blue/green — группы версий; готовность проверяется до переключения. Данные и секреты не должны
# сбрасываться при обновлении кода.
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
id kiriktasks >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/kirik-tasks --shell /usr/sbin/nologin kiriktasks
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -d -m 755 /opt/kirik-tasks/releases /opt/kirik-tasks/instances /etc/nginx/kirik-tasks
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -d -m 750 -o root -g kiriktasks /etc/kirik-tasks
if [[ ! -f /etc/kirik-tasks/common.env ]]; then
    lab_db_password=$(openssl rand -hex 24)
    lab_jwt_secret=$(openssl rand -hex 32)
    # Секреты не печатаются и не попадают в Git.
    # Записываем общий DSN и JWT-секрет в отдельный защищённый env. Это постоянные параметры: повторная
    # генерация сломала бы действующие сессии/доступ БД.
    printf 'DATABASE_URL=postgresql://kirik_tasks:%s@127.0.0.1:5432/kirik_tasks\nJWT_SECRET=%s\n' \
        "$lab_db_password" "$lab_jwt_secret" > /etc/kirik-tasks/common.env
    chown root:kiriktasks /etc/kirik-tasks/common.env
    chmod 640 /etc/kirik-tasks/common.env
    # Далее heredoc передаёт SQL в psql под системным postgres. Сначала создаётся роль, затем БД при их
    # отсутствии; %L безопасно экранирует пароль, а gexec исполняет сгенерированную команду.
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -v lab_password="$lab_db_password" <<'SQL'
SELECT format('CREATE ROLE kirik_tasks LOGIN PASSWORD %L', :'lab_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='kirik_tasks') \gexec
SELECT 'CREATE DATABASE kirik_tasks OWNER kirik_tasks'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='kirik_tasks') \gexec
SQL
fi
# Изолируем Python-зависимости сервера от системных библиотек Ubuntu.
python3 -m venv /opt/kirik-tasks/venv
# Устанавливаем зафиксированные версии в venv; может потребоваться доступ к репозиторию пакетов.
/opt/kirik-tasks/venv/bin/python -m pip install -r "$lab_root/backend/requirements.txt"
for lab_release in 1.0.0 2.0.0; do
    lab_dir="/opt/kirik-tasks/releases/$lab_release"
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
    if [[ $lab_color == blue ]]; then lab_version=1.0.0; lab_port=9300; else lab_version=2.0.0; lab_port=9400; fi
    for lab_number in 1 2; do
        lab_name="$lab_color-$lab_number"
        # Ссылка выбирает релиз или конфигурацию без переписывания опубликованного содержимого.
        ln -sfn "/opt/kirik-tasks/releases/$lab_version" "/opt/kirik-tasks/instances/$lab_name"
        printf 'PORT=%s\n' "$((lab_port + lab_number))" > "/etc/kirik-tasks/$lab_name.env"
    done
done
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 600 "$lab_root/certificates/server.key" /etc/kirik-tasks/server.key
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/certificates/server.crt" /etc/kirik-tasks/server.crt
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/deploy/systemd/kirik-tasks@.service" /etc/systemd/system/kirik-tasks@.service
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/deploy/nginx/blue.conf" /etc/nginx/kirik-tasks/blue.conf
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/deploy/nginx/green.conf" /etc/nginx/kirik-tasks/green.conf
[[ -L /etc/nginx/kirik-tasks/active.conf ]] || ln -s blue.conf /etc/nginx/kirik-tasks/active.conf
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/deploy/nginx/kirik-tasks.conf" /etc/nginx/sites-available/kirik-tasks.conf
# Ссылка выбирает релиз или конфигурацию без переписывания опубликованного содержимого.
ln -sfn /etc/nginx/sites-available/kirik-tasks.conf /etc/nginx/sites-enabled/kirik-tasks.conf
# Перечитываем unit-файлы systemd. Сама команда не перезапускает уже работающий backend.
systemctl daemon-reload
# Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
systemctl enable --now kirik-tasks@blue-1 kirik-tasks@blue-2
for lab_port in 9301 9302; do
    lab_ready=false
    for lab_attempt in {1..30}; do
        # Готовность /ready проверяется с тайм-аутом и ограниченным числом попыток. Открытый порт ещё не
        # означает доступную БД.
        if curl -fsS --max-time 2 "http://127.0.0.1:$lab_port/ready" >/dev/null; then lab_ready=true; break; fi
        # Пауза между ограниченными проверками. Готовность определяется следующим запросом, а не только
        # истечением времени.
        sleep 1
    done
    $lab_ready || { echo "Инстанс на $lab_port не готов: journalctl -u kirik-tasks@blue-1 -u kirik-tasks@blue-2"; exit 1; }
done
# Проверяем синтаксис перед reload: неверная конфигурация не должна становиться активной.
nginx -t
# Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
systemctl enable nginx postgresql
# Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
systemctl reload nginx
echo 'Готово: два blue backend, nginx HTTPS :9543, общая PostgreSQL.'
