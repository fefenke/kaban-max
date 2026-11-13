#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-0.1.5}"
core_version="$(sed -n 's/^package_version=//p' "$repo/core/UPSTREAM")"
core_commit="$(sed -n 's/^commit=//p' "$repo/core/UPSTREAM")"
output="${2:-$repo/dist/release}"
export PO2LMO="${PO2LMO:-$(command -v po2lmo)}"
test -x "$PO2LMO"
(cd "$repo/fe-app-kabanmax" && npm ci --ignore-scripts --no-audit --no-fund && npm run build)
bash "$repo/scripts/build-zapret2-local.sh" "$version" "$output"
for variant in ${CORE_VARIANTS:-base tiny}; do
 bash "$repo/scripts/build-core.sh" "$variant" aarch64_cortex-a53 "$output"
done
cat > "$output/core-release.json" <<EOF
{"schema":1,"name":"sing-box-kabanmax","version":"$core_version","tag":"$version","page":"https://github.com/fefenke/kaban-max/releases/tag/$version","requires":{"kabanmax":"$version"},"source_commit":"$core_commit"}
EOF
(cd "$output" && sha256sum *.ipk *.apk install.sh release.json core-release.json > SHA256SUMS)
bash "$repo/scripts/check-release.sh" "$output"
