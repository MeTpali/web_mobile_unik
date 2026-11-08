#!/usr/bin/env bash
# Сценарий подготовки и сборки. Приватный key остаётся на сервере, публичный crt передаётся клиенту.
# SAN перечисляет адреса, с которыми проверяется подлинность сервера.
# Строгий Bash: -e прерывает необработанную ошибку, -u запрещает неопределённую переменную, pipefail
# учитывает сбой внутри конвейера.
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ -e server.key || -e server.crt ]]; then
  echo 'Сертификат уже существует. Для замены сначала перенесите server.key/server.crt в резервную папку.' >&2
  exit 1
fi
# Передайте ВСЕ IP, по которым сервер будут открывать браузер и приложение.
# Начинаем SAN с localhost/loopback; добавленные IP должны соответствовать реальным адресам клиента.
san='DNS:localhost,IP:127.0.0.1'
# Добавляем каждый переданный IP как IP SAN. CN сам по себе не заменяет проверку адреса.
for address in "$@"; do san="$san,IP:$address"; done
# Ограничиваем права новых файлов: приватный ключ не должен стать общедоступным.
umask 077
# Создаём RSA-ключ и самоподписанный X.509. SAN ниже задаёт допустимые адреса сервера.
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 365 \
  -keyout server.key -out server.crt -subj '/CN=Tasks Lab Server' \
  -addext "subjectAltName=$san" \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign' \
  -addext 'extendedKeyUsage=serverAuth'
echo 'Созданы server.crt (публичный) и server.key (только на сервере).'
