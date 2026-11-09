#!/usr/bin/env bash
# Проверка готовности, переключение blue-green и откат. Сценарий работает на компьютере, не телефоне.
# Blue/green — группы версий; готовность проверяется до переключения. Данные и секреты не должны
# сбрасываться при обновлении кода.
# Проверяем оба новых процесса ДО reload. При неудаче сохраняем старый upstream.
# Строгий Bash: -e прерывает необработанную ошибку, -u запрещает неопределённую переменную, pipefail
# учитывает сбой внутри конвейера.
set -euo pipefail
# Проверяем root до изменения системных файлов. GUI телефона не требует таких прав.
[[ $EUID -eq 0 ]] || { echo 'Нужен sudo'; exit 1; }
# Читаем цвет группы из аргумента; ${...:?...} требует обязательное значение.
lab_color=${1:?Укажите blue или green}
[[ $lab_color == blue || $lab_color == green ]] || exit 2
# Открываем дескриптор файла блокировки для следующего flock.
exec 9>/run/lock/tasks-release.lock
# Блокируем одновременное развёртывание; блокировка удерживается до завершения процесса.
flock 9
if [[ $lab_color == blue ]]; then lab_ports='9301 9302'; lab_other=green; else lab_ports='9401 9402'; lab_other=blue; fi
# Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
systemctl start "kirik-tasks@$lab_color-1" "kirik-tasks@$lab_color-2"
for lab_port in $lab_ports; do
    lab_ok=false
    for lab_attempt in {1..20}; do
        # Готовность /ready проверяется с тайм-аутом и ограниченным числом попыток. Открытый порт ещё не
        # означает доступную БД.
        if curl -fsS --max-time 2 "http://127.0.0.1:$lab_port/ready" >/dev/null; then lab_ok=true; break; fi
        # Пауза между ограниченными проверками. Готовность определяется следующим запросом, а не только
        # истечением времени.
        sleep 1
    done
    $lab_ok || { echo "Новая версия не готова на порту $lab_port. Трафик не переключён."; exit 1; }
done
lab_old=$(readlink /etc/nginx/kirik-tasks/active.conf)
# Ссылка выбирает релиз или конфигурацию без переписывания опубликованного содержимого.
ln -s "$lab_color.conf" /etc/nginx/kirik-tasks/active.next
# Атомарная замена active-ссылки: nginx не должен увидеть частично записанное состояние.
mv -Tf /etc/nginx/kirik-tasks/active.next /etc/nginx/kirik-tasks/active.conf
if ! nginx -t || ! systemctl reload nginx; then
    # Ссылка выбирает релиз или конфигурацию без переписывания опубликованного содержимого.
    ln -sfn "$lab_old" /etc/nginx/kirik-tasks/active.conf
    echo 'Переключение отменено; сохранена прежняя конфигурация.'; exit 1
fi
# Выбранная группа должна подниматься после перезагрузки ПК.
# Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
systemctl enable "kirik-tasks@$lab_color-1" "kirik-tasks@$lab_color-2"
# Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
systemctl disable "kirik-tasks@$lab_other-1" "kirik-tasks@$lab_other-2"
echo "Трафик направлен в $lab_color. Старая группа ещё работает для завершения запросов."
echo "После проверки: sudo systemctl stop kirik-tasks@$lab_other-1 kirik-tasks@$lab_other-2"
