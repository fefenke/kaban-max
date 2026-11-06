#!/usr/bin/env bash
# Build only the Russian catalog for an already installed UI version.
# Usage: bash scripts/build-i18n-local.sh /path/to/po2lmo [ui-version]
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
po2lmo="${1:?Pass the upstream LuCI po2lmo executable}"
version="${2:-0.1.0}"
output="${3:-$repo/dist/zapret2-local}"
mkdir -p "$output"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
source <(sed -e '/^main "\$@"$/d' -e 's|^ROOT_DIR=.*|ROOT_DIR="$repo"|' "$repo/build.sh") "$version" "$output"
ROOT_DIR="$repo"
build_i18n_root "$work/root" "$po2lmo"
test -s "$work/root/usr/lib/lua/luci/i18n/kabanmax.ru.lmo"
write_i18n_ipk_control "$work/control" "$(installed_size_bytes "$work/root")"
mkdir -p "$work/packed"
printf '2.0\n' > "$work/packed/debian-binary"
tar --owner=0 --group=0 -czf "$work/packed/control.tar.gz" -C "$work/control" .
tar --owner=0 --group=0 -czf "$work/packed/data.tar.gz" -C "$work/root" .
tar --owner=0 --group=0 -czf "$output/luci-i18n-kabanmax-ru_${version}_all.ipk" -C "$work/packed" debian-binary control.tar.gz data.tar.gz
verify_ipk_metadata "$output/luci-i18n-kabanmax-ru_${version}_all.ipk" luci-i18n-kabanmax-ru "$version"
write_i18n_apk_scripts "$work/scripts"
generate_apk_metadata_files luci-i18n-kabanmax-ru "$work/root"
apk mkpkg --files "$work/root" --output "$output/luci-i18n-kabanmax-ru_${version}_all.apk" \
    -I name:luci-i18n-kabanmax-ru -I "version:$version" -I arch:noarch \
    -I license:GPL-2.0-or-later -I 'description:Russian translation for K.A.B.A.N.-MAX' \
    -I "depends:libc luci-app-kabanmax>=${version}" -I origin:kabanmax \
    -s "pre-install:$work/scripts/i18n-pre-install.sh" \
    -s "post-install:$work/scripts/i18n-post-install.sh" \
    -s "pre-deinstall:$work/scripts/i18n-pre-deinstall.sh" \
    -s "pre-upgrade:$work/scripts/i18n-pre-upgrade.sh" \
    -s "post-upgrade:$work/scripts/i18n-post-upgrade.sh"
verify_apk_metadata "$(command -v apk)" "$output/luci-i18n-kabanmax-ru_${version}_all.apk" luci-i18n-kabanmax-ru "$version"
sha256sum "$output/luci-i18n-kabanmax-ru_${version}_all.apk"
