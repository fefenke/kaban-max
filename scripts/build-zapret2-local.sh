#!/usr/bin/env bash
# Package architecture-independent KabanMax files with existing upstream control scripts.
# Needs bash, GNU coreutils/tar, a built frontend and apk-tools v3 for .apk output.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-0.1.2}"
output="${2:-$repo/dist/zapret2-local}"
[[ "$output" = /* ]] || output="$PWD/$output"
mkdir -p "$output"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
# Source the packaging functions, without the SDK-downloading main entry point.
source <(sed -e '/^main "\$@"$/d' -e 's|^ROOT_DIR=.*|ROOT_DIR="$repo"|' "$repo/build.sh") "$version" "$output"
ROOT_DIR="$repo"
BUILD_DIR="$work"
for kind in backend app; do
    root="$work/$kind"
    control="$work/$kind-control"
    "build_${kind}_root" "$root"
    "write_${kind}_ipk_control" "$control" "$(installed_size_bytes "$root")"
    name=kabanmax
    [[ "$kind" = app ]] && name=luci-app-kabanmax
    packed="$work/$kind-packed"
    mkdir -p "$packed"
    printf '2.0\n' > "$packed/debian-binary"
    tar --owner=0 --group=0 -czf "$packed/control.tar.gz" -C "$control" .
    tar --owner=0 --group=0 -czf "$packed/data.tar.gz" -C "$root" .
    tar --owner=0 --group=0 -czf "$output/${name}_${version}_all.ipk" -C "$packed" debian-binary control.tar.gz data.tar.gz
    verify_ipk_metadata "$output/${name}_${version}_all.ipk" "$name" "$version"
done

if (apk mkpkg --help 2>&1 || true) | grep -q mkpkg; then
    scripts="$work/apk-scripts"
    write_backend_apk_scripts "$scripts"
    write_app_apk_scripts "$scripts"
    for kind in backend app; do
        name=kabanmax
        depends="$BACKEND_DEPENDS_APK"
        [[ "$kind" = app ]] && { name=luci-app-kabanmax; depends="$APP_DEPENDS_APK"; }
        generate_apk_metadata_files "$name" "$work/$kind" "$([[ "$kind" = backend ]] && echo /etc/config/kabanmax || true)"
        apk mkpkg --files "$work/$kind" --output "$output/${name}_${version}_all.apk" \
            -I "name:$name" -I "version:$version" -I arch:noarch -I license:GPL-2.0-or-later \
            -I "description:K.A.B.A.N.-MAX routing with Zapret2 and stable fallback" \
            -I "depends:$depends" -I origin:kabanmax \
            -s "pre-install:$scripts/$kind-pre-install.sh" \
            -s "post-install:$scripts/$kind-post-install.sh" \
            -s "pre-deinstall:$scripts/$kind-pre-deinstall.sh" \
            -s "pre-upgrade:$scripts/$kind-pre-upgrade.sh" \
            -s "post-upgrade:$scripts/$kind-post-upgrade.sh"
        verify_apk_metadata "$(command -v apk)" "$output/${name}_${version}_all.apk" "$name" "$version"
    done
fi
if [[ -n "${PO2LMO:-}" ]]; then
    bash "$repo/scripts/build-i18n-local.sh" "$PO2LMO" "$version" "$output"
else
    printf 'Russian catalog not packaged: set PO2LMO to the upstream LuCI converter executable.\n' >&2
fi
write_release_files "$output"
(cd "$output" && shopt -s nullglob && sha256sum *.ipk *.apk install.sh release.json > SHA256SUMS)
printf 'Local test packages: %s\n' "$output"
