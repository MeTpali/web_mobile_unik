#!/usr/bin/env bash
# Новая версия получает отдельную папку. Уже опубликованный снимок не перезаписывается.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Нужен sudo'; exit 1; }
lab_color=${1:?blue или green}
lab_version=${2:?Номер новой версии}
[[ $lab_color == blue || $lab_color == green ]] || exit 2
[[ $lab_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
lab_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
if [[ -n ${SUDO_UID:-} && -d "$lab_root/docs" ]]; then
    chown "$SUDO_UID:$SUDO_GID" "$lab_root/docs"
fi
lab_dir="/opt/expenses-lab/releases/$lab_version"
[[ ! -e "$lab_dir" ]] || { echo "Версия $lab_version уже существует: выберите новый номер"; exit 1; }
exec 9>/run/lock/expenses-release.lock
flock 9
install -m 644 "$lab_root/deploy/systemd/expenses@.service" /etc/systemd/system/expenses@.service
systemctl daemon-reload
install -d "$lab_dir/backend"
cp -r "$lab_root/backend/app" "$lab_root/backend/static" "$lab_dir/backend/"
if [[ $lab_color == green ]]; then lab_features='["summary"]'; lab_base=9200; else lab_features='[]'; lab_base=9100; fi
printf '{"version":"%s","features":%s}\n' "$lab_version" "$lab_features" > "$lab_dir/backend/app/release.json"
for lab_number in 1 2; do
    ln -sfn "$lab_dir" "/opt/expenses-lab/instances/$lab_color-$lab_number"
    # Обновляем процессы по одному; второй продолжает обслуживать nginx.
    systemctl restart "expenses@$lab_color-$lab_number"
    lab_ok=false
    for lab_attempt in {1..25}; do
        if curl -fsS --max-time 2 "http://127.0.0.1:$((lab_base + lab_number))/ready" >/dev/null; then lab_ok=true; break; fi
        sleep 1
    done
    $lab_ok || { echo 'Экземпляр не готов. Переключение nginx не выполнялось.'; exit 1; }
done
echo "Группа $lab_color готова с версией $lab_version. Маршрутизация nginx не изменялась."
