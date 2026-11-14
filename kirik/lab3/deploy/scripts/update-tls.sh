#!/usr/bin/env bash
# Проверка новой пары TLS, резервная копия, reload nginx и откат при ошибке. Сценарий работает на
# компьютере, не телефоне. Blue/green — группы версий; готовность проверяется до переключения. Данные
# и секреты не должны сбрасываться при обновлении кода.
# Обновляет только сертификат nginx; backend, БД и выбранный релиз не меняются.
# Строгий Bash: -e прерывает необработанную ошибку, -u запрещает неопределённую переменную, pipefail
# учитывает сбой внутри конвейера.
set -euo pipefail
# Проверяем root до изменения системных файлов. GUI телефона не требует таких прав.
[[ $EUID -eq 0 ]] || { echo 'Запустите через sudo'; exit 1; }
# Находим корень относительно файла скрипта, а не произвольного текущего каталога запуска.
lab_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
lab_tls_dir=/etc/kirik-tasks
[[ -f "$lab_tls_dir/server.crt" && -f "$lab_tls_dir/server.key" ]] || {
  echo 'Сначала разверните инфраструктуру ЛР3'; exit 1;
}
# Проверяем сертификат перед установкой. Соответствие приватному ключу проверяется отдельно.
openssl verify -CAfile "$lab_root/certificates/server.crt" "$lab_root/certificates/server.crt"
cmp <(openssl x509 -in "$lab_root/certificates/server.crt" -pubkey -noout) \
    <(openssl pkey -in "$lab_root/certificates/server.key" -pubout)
# Открываем дескриптор файла блокировки для следующего flock.
exec 9>/run/lock/kirik-tasks-tls.lock
# Блокируем одновременное развёртывание; блокировка удерживается до завершения процесса.
flock 9
lab_backup=$(mktemp -d "$lab_tls_dir/tls-backup-XXXXXXXX")
chmod 700 "$lab_backup"
cp -a "$lab_tls_dir/server.crt" "$lab_tls_dir/server.key" "$lab_backup/"
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 600 "$lab_root/certificates/server.key" "$lab_tls_dir/server.key"
# Копируем файлы/создаём каталоги с явными правами и владельцем. Это изменение инфраструктуры на ПК.
install -m 644 "$lab_root/certificates/server.crt" "$lab_tls_dir/server.crt"
if ! nginx -t || ! systemctl reload nginx; then
  cp -a "$lab_backup/server.crt" "$lab_backup/server.key" "$lab_tls_dir/"
  # Управляем службами стенда: start/restart действует сейчас, enable/disable определяет автозапуск.
  systemctl reload nginx || true
  echo "Обновление не удалось, прежние сертификат и ключ восстановлены: $lab_backup" >&2
  exit 1
fi
echo "TLS nginx обновлён. Резервная копия: $lab_backup"
