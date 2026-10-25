#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ -e server.key || -e server.crt ]]; then
  echo 'Сертификат уже существует. Для замены сначала перенесите server.key/server.crt в резервную папку.' >&2
  exit 1
fi
# Передайте ВСЕ IP, по которым сервер будут открывать браузер и приложение.
san='DNS:localhost,IP:127.0.0.1'
for address in "$@"; do san="$san,IP:$address"; done
umask 077
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 365 \
  -keyout server.key -out server.crt -subj '/CN=Tasks Lab Server' \
  -addext "subjectAltName=$san" \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign' \
  -addext 'extendedKeyUsage=serverAuth'
echo 'Созданы server.crt (публичный) и server.key (только на сервере).'
