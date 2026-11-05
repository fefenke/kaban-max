#!/usr/bin/env bash
# Apply our small reviewed patch to a pinned upstream tree, then use its build.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-base}"
architecture="${2:-aarch64_cortex-a53}"
output="${3:-$repo/dist/release}"
case "$variant" in base|tiny|full) ;; *) echo 'Unknown core variant' >&2; exit 2;; esac
case "$architecture" in aarch64_cortex-a53|x86_64) ;; *) echo 'Architecture not validated by this release' >&2; exit 2;; esac
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
source_repo="$(sed -n 's/^repository=//p' "$repo/core/UPSTREAM")"
commit="$(sed -n 's/^commit=//p' "$repo/core/UPSTREAM")"
version="$(sed -n 's/^package_version=//p' "$repo/core/UPSTREAM")"
if [[ -n "${CORE_SOURCE:-}" ]]; then
 git clone --shared "$CORE_SOURCE" "$work/source"
 git -C "$work/source" checkout --detach "$commit"
else
 git init -q "$work/source"
 git -C "$work/source" fetch --depth=1 "$source_repo" "$commit"
 git -C "$work/source" checkout -q --detach FETCH_HEAD
fi
git -C "$work/source" apply --check "$repo/core/patches/0001-stable-fallback.patch"
git -C "$work/source" apply "$repo/core/patches/0001-stable-fallback.patch"
export SOURCE_DATE_EPOCH=1793880000
mkdir -p "$output"
bash "$work/source/build.sh" --variant "$variant" --arch "$architecture" --version "$version" --format all --output "$output"
