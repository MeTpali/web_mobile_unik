#!/usr/bin/env bash
set -euo pipefail
lab_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
lab_psdk=${LAB_PSDK:-"$HOME/AuroraPlatformSDK/sdks/aurora_psdk"}
lab_sdk=${LAB_SDK:-"$HOME/AuroraOS"}
lab_target=${LAB_TARGET:-AuroraOS-5.2.1.200-base-armv7hl}
if [[ ! -f "$lab_root/certificates/server.crt" ]]; then
  echo 'Сначала создайте HTTPS-сертификат: bash certificates/generate.sh <IP-ПК>' >&2
  exit 1
fi
cd "$lab_root/client"
# --no-pull-build-requires использует уже подготовленный target без загрузки пакетов.
"$lab_psdk/sdk-chroot" mb2 -t "$lab_target" --no-pull-build-requires build > build.log 2>&1 || {
  tail -60 build.log >&2
  exit 1
}
lab_version=$(awk '/^Version:/ {print $2}' rpm/ru.kirik.taskslab3.spec)
lab_release=$(awk '/^Release:/ {print $2}' rpm/ru.kirik.taskslab3.spec)
lab_rpm="$lab_root/client/RPMS/ru.kirik.taskslab3-$lab_version-$lab_release.armv7hl.rpm"
bash "$lab_root/tools/sign_package.sh" "$lab_rpm"
echo "Готов подписанный пакет: $lab_rpm"
