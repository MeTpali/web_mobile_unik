#!/usr/bin/env bash
# Проверяем оба новых процесса ДО reload. При неудаче сохраняем старый upstream.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Нужен sudo'; exit 1; }
lab_color=${1:?Укажите blue или green}
[[ $lab_color == blue || $lab_color == green ]] || exit 2
exec 9>/run/lock/tasks-release.lock
flock 9
if [[ $lab_color == blue ]]; then lab_ports='9301 9302'; lab_other=green; else lab_ports='9401 9402'; lab_other=blue; fi
systemctl start "kirik-tasks@$lab_color-1" "kirik-tasks@$lab_color-2"
for lab_port in $lab_ports; do
    lab_ok=false
    for lab_attempt in {1..20}; do
        if curl -fsS --max-time 2 "http://127.0.0.1:$lab_port/ready" >/dev/null; then lab_ok=true; break; fi
        sleep 1
    done
    $lab_ok || { echo "Новая версия не готова на порту $lab_port. Трафик не переключён."; exit 1; }
done
lab_old=$(readlink /etc/nginx/kirik-tasks/active.conf)
ln -s "$lab_color.conf" /etc/nginx/kirik-tasks/active.next
mv -Tf /etc/nginx/kirik-tasks/active.next /etc/nginx/kirik-tasks/active.conf
if ! nginx -t || ! systemctl reload nginx; then
    ln -sfn "$lab_old" /etc/nginx/kirik-tasks/active.conf
    echo 'Переключение отменено; сохранена прежняя конфигурация.'; exit 1
fi
# Выбранная группа должна подниматься после перезагрузки ПК.
systemctl enable "kirik-tasks@$lab_color-1" "kirik-tasks@$lab_color-2"
systemctl disable "kirik-tasks@$lab_other-1" "kirik-tasks@$lab_other-2"
echo "Трафик направлен в $lab_color. Старая группа ещё работает для завершения запросов."
echo "После проверки: sudo systemctl stop kirik-tasks@$lab_other-1 kirik-tasks@$lab_other-2"
