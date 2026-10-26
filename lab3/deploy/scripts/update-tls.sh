#!/usr/bin/env bash
# Обновляет только сертификат nginx; backend, БД и выбранный релиз не меняются.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Запустите через sudo'; exit 1; }
lab_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
lab_tls_dir=/etc/expenses-lab
[[ -f "$lab_tls_dir/server.crt" && -f "$lab_tls_dir/server.key" ]] || {
  echo 'Сначала разверните инфраструктуру ЛР3'; exit 1;
}
openssl verify -CAfile "$lab_root/certificates/server.crt" "$lab_root/certificates/server.crt"
cmp <(openssl x509 -in "$lab_root/certificates/server.crt" -pubkey -noout) \
    <(openssl pkey -in "$lab_root/certificates/server.key" -pubout)
exec 9>/run/lock/expenses-tls.lock
flock 9
lab_backup=$(mktemp -d "$lab_tls_dir/tls-backup-XXXXXXXX")
chmod 700 "$lab_backup"
cp -a "$lab_tls_dir/server.crt" "$lab_tls_dir/server.key" "$lab_backup/"
install -m 600 "$lab_root/certificates/server.key" "$lab_tls_dir/server.key"
install -m 644 "$lab_root/certificates/server.crt" "$lab_tls_dir/server.crt"
if ! nginx -t || ! systemctl reload nginx; then
  cp -a "$lab_backup/server.crt" "$lab_backup/server.key" "$lab_tls_dir/"
  systemctl reload nginx || true
  echo "Обновление не удалось, прежние сертификат и ключ восстановлены: $lab_backup" >&2
  exit 1
fi
echo "TLS nginx обновлён. Резервная копия: $lab_backup"
