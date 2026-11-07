#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-0.1.1}"
output="${2:-$repo/dist/release}"
export PO2LMO="${PO2LMO:-$(command -v po2lmo)}"
test -x "$PO2LMO"
(cd "$repo/fe-app-kabanmax" && npm ci --ignore-scripts --no-audit --no-fund && npm run build)
bash "$repo/scripts/build-zapret2-local.sh" "$version" "$output"
for variant in ${CORE_VARIANTS:-base tiny}; do
 bash "$repo/scripts/build-core.sh" "$variant" aarch64_cortex-a53 "$output"
done
cat > "$output/core-release.json" <<EOF
{"schema":1,"name":"sing-box-kabanmax","version":"1.14.4-r6","tag":"$version","page":"https://github.com/fefenke/kaban-max/releases/tag/$version","requires":{"kabanmax":"$version"},"source_commit":"60d96c99815a672712915a5c00114bf0f690ad80"}
EOF
(cd "$output" && sha256sum *.ipk *.apk install.sh release.json core-release.json > SHA256SUMS)
bash "$repo/scripts/check-release.sh" "$output"
