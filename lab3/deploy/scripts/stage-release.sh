#!/usr/bin/env bash
# Создание неизменяемого релиза. Сценарий работает на компьютере, не телефоне. Blue/green — группы
# версий; готовность проверяется до переключения. Данные и секреты не должны сбрасываться при
# обновлении кода.
# Новая версия получает отдельную папку. Уже опубликованный снимок не перезаписывается.
# Строгий Bash: -e прерывает необработанную ошибку, -u запрещает неопределённую переменную, pipefail
# учитывает сбой внутри конвейера.
set -euo pipefail
# Проверяем root до изменения системных файлов. GUI телефона не требует таких прав.
[[ $EUID -eq 0 ]] || { echo 'Нужен sudo'; exit 1; }
# Читаем цвет группы из аргумента; ${...:?...} требует обязательное значение.
lab_color=${1:?blue или green}
# Номер релиза из аргумента проверяется до создания каталога. Опубликованную версию не переписываем.
lab_version=${2:?Номер новой версии}
[[ $lab_color == blue || $lab_color == green ]] || exit 2
[[ $lab_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
# Находим корень относительно файла скрипта, а не произвольного текущего каталога запуска.
lab_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
if [[ -n ${SUDO_UID:-} && -d "$lab_root/docs" ]]; then
    chown "$SUDO_UID:$SUDO_GID" "$lab_root/docs"
fi
lab_dir="/opt/expenses-lab/releases/$lab_version"
[[ ! -e "$lab_dir" ]] || { echo "Версия $lab_version уже существует: выберите новый номер"; exit 1; }
# Открываем дескриптор файла блокировки для следующего flock.
exec 9>/run/lock/expenses-release.lock
# Блокируем одновременное развёртывание; блокировка удерживается до завершения процесса.
flock 9
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/deploy/systemd/expenses@.service" /etc/systemd/system/expenses@.service
# Перечитываем unit-файлы systemd. Сама команда не перезапускает уже работающий backend.
systemctl daemon-reload
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -d "$lab_dir/backend"
# Копируем app/static в новый снимок релиза. Изменения исходников после копирования не изменят уже
# опубликованную версию.
cp -r "$lab_root/backend/app" "$lab_root/backend/static" "$lab_dir/backend/"
if [[ $lab_color == green ]]; then lab_features='["summary"]'; lab_base=9200; else lab_features='[]'; lab_base=9100; fi
# release.json фиксирует версию и включённые возможности снимка. Backend читает его при запуске, а не
# получает версию из названия GUI.
printf '{"version":"%s","features":%s}\n' "$lab_version" "$lab_features" > "$lab_dir/backend/app/release.json"
for lab_number in 1 2; do
    # Ссылка выбирает релиз или конфигурацию без переписывания опубликованного содержимого.
    ln -sfn "$lab_dir" "/opt/expenses-lab/instances/$lab_color-$lab_number"
    # Обновляем процессы по одному; второй продолжает обслуживать nginx.
    # Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
    systemctl restart "expenses@$lab_color-$lab_number"
    lab_ok=false
    for lab_attempt in {1..25}; do
        # Готовность /ready проверяется с тайм-аутом и ограниченным числом попыток. Открытый порт ещё не
        # означает доступную БД.
        if curl -fsS --max-time 2 "http://127.0.0.1:$((lab_base + lab_number))/ready" >/dev/null; then lab_ok=true; break; fi
        # Пауза между ограниченными проверками. Готовность определяется следующим запросом, а не только
        # истечением времени.
        sleep 1
    done
    $lab_ok || { echo 'Экземпляр не готов. Переключение nginx не выполнялось.'; exit 1; }
done
echo "Группа $lab_color готова с версией $lab_version. Маршрутизация nginx не изменялась."
