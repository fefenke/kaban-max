#!/usr/bin/env bash
# Synthetic files exercise manifest compatibility, not package/runtime validation.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
task_tmp=$(mktemp -d)
trap 'rm -rf -- "$task_tmp"' EXIT
for ext in apk ipk; do
  for name in kabanmax luci-app-kabanmax luci-i18n-kabanmax-ru; do
    printf 'synthetic\n' > "$task_tmp/${name}_0.1.6_all.$ext"
  done
  for variant in base tiny; do
    printf 'synthetic\n' > "$task_tmp/sing-box-kabanmax_1.14.4-r11_${variant}_aarch64_cortex-a53.$ext"
  done
done
printf 'synthetic\n' > "$task_tmp/install.sh"
printf '%s\n' '{"version":"1.14.4-r11","tag":"0.1.6","requires":{"kabanmax":"0.1.6"}}' > "$task_tmp/core-release.json"
manifest() {
  printf '{"version":"0.1.6","tag":"0.1.6","requires":{"sing-box-kabanmax":"%s"}}\n' "$1" > "$task_tmp/release.json"
  (cd "$task_tmp" && sha256sum *.apk *.ipk install.sh release.json core-release.json > SHA256SUMS)
}
for minimum in 1.14.4-r10 1.14.4-r11; do
  manifest "$minimum"
  bash "$repo/scripts/check-release.sh" "$task_tmp" >/dev/null
done
manifest 1.14.4-r12
if bash "$repo/scripts/check-release.sh" "$task_tmp" >/dev/null 2>&1; then
  echo 'Accepted core older than required minimum' >&2
  exit 1
fi
echo 'Release minimum/core compatibility and rejected downgrade: OK'
