#!/usr/bin/env bash
# Подпись RPM штатной командой SDK. Импорты подключают зависимости; основной код выполняет одну роль в
# цепочке приложения.
# В этом SDK штатный инструмент называется rpmsign-external.
# Это явная обёртка для этапа sign_package из задания, а не другой механизм подписи.
# Строгий Bash: -e прерывает необработанную ошибку, -u запрещает неопределённую переменную, pipefail
# учитывает сбой внутри конвейера.
set -euo pipefail
lab_psdk=${LAB_PSDK:-"$HOME/AuroraPlatformSDK/sdks/aurora_psdk"}
lab_sdk=${LAB_SDK:-"$HOME/AuroraOS"}
# Подписываем готовый RPM ключом разработчика. Подпись пакета отличается от TLS-сертификата API.
"$lab_psdk/sdk-chroot" rpmsign-external sign \
    --key "$lab_sdk/package-signing/regular_key.pem" \
    --cert "$lab_sdk/package-signing/regular_cert.pem" "$@"
# Проверяем подпись именно конечного RPM после пересборки.
"$lab_psdk/sdk-chroot" rpmsign-external verify "$@"
