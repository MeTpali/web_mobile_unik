#!/usr/bin/env bash
# В этом SDK штатный инструмент называется rpmsign-external.
# Это явная обёртка для этапа sign_package из задания, а не другой механизм подписи.
set -euo pipefail
lab_psdk=${LAB_PSDK:-"$HOME/AuroraPlatformSDK/sdks/aurora_psdk"}
lab_sdk=${LAB_SDK:-"$HOME/AuroraOS"}
"$lab_psdk/sdk-chroot" rpmsign-external sign \
    --key "$lab_sdk/package-signing/regular_key.pem" \
    --cert "$lab_sdk/package-signing/regular_cert.pem" "$@"
"$lab_psdk/sdk-chroot" rpmsign-external verify "$@"
