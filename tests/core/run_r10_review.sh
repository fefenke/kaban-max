#!/bin/sh
# Offline, isolated r10 verification/build. /output must be a dedicated directory.
set -eu
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
taskCommit=$(sed -n 's/^commit=//p' /core/UPSTREAM | tr -d '\r')
git -c safe.directory=/source -C /source archive "$taskCommit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for patch in /core/patches/*.patch; do
    git apply --check "$patch"
    git apply "$patch"
    sha256sum "$patch"
done
python3 /scripts/brand-core.py "$taskTmp"
# The upstream builder checks line endings with git ls-files, even for archives.
# A temporary index is sufficient; no commit or source checkout is modified.
git init -q
git add '*.go'
export GOPROXY=off SOURCE_DATE_EPOCH=1793880000
# All group tests, including the stable-fallback patch's own regressions.
go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./protocol/group ./experimental/cachefile
bash build.sh --variant base --arch x86_64 --version 1.14.4-r10 --binary-only --output /output
/output/build/amd64/base/sing-box version
bash build.sh --variant base --arch aarch64_cortex-a53 --version 1.14.4-r10 --binary-only --output /output
find /output/build -type f -name sing-box -exec sha256sum '{}' ';'
