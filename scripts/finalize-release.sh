#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$repo/dist/release}"
(cd "$output" && sha256sum *.ipk *.apk install.sh release.json core-release.json > SHA256SUMS)
bash "$repo/scripts/check-release.sh" "$output"
