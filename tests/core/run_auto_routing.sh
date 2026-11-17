#!/bin/sh
set -eu
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
taskCommit=$(sed -n 's/^commit=//p' /core/UPSTREAM | tr -d '\r')
git -c safe.directory=/source -C /source archive "$taskCommit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for p in /core/patches/*.patch; do git apply --check "$p"; git apply "$p"; done
mkdir -p common/autoroute
cp /extra-tests/auto_routing_test.go common/autoroute/
cp /extra-tests/auto_web_test.go common/autoroute/
cp /extra-tests/auto_registry_test.go common/autoroute/
cp /extra-tests/auto_repair_test.go common/autoroute/
cp /extra-tests/auto_ip_failure_test.go common/autoroute/
cp /extra-tests/auto_dial_isolation_test.go common/autoroute/
cp /extra-tests/auto_timeout_test.go common/autoroute/
cp /extra-tests/auto_manual_test.go common/autoroute/
cp /extra-tests/auto_original_context_test.go common/autoroute/
cp /extra-tests/auto_ip_registry_test.go common/autoroute/
cp /extra-tests/auto_field_regression_test.go common/autoroute/
cp /extra-tests/auto_quic_field_test.go common/autoroute/
cp /extra-tests/auto_ja3_alpn_test.go common/ja3/
cp /extra-tests/auto_sniff_alpn_test.go common/sniff/
cp /extra-tests/auto_dns_identity_test.go route/
cp /extra-tests/auto_fakeip_identity_test.go route/
taskVersion=$(sed -n 's/^package_version=//p' /core/UPSTREAM | tr -d '\r')
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute ./route ./experimental/clashapi ./protocol/group ./experimental/cachefile ./common/ja3 ./common/sniff
if [ "${AUTO_BUILD:-0}" = 1 ]; then
    python3 /scripts/brand-core.py "$taskTmp"
    git init -q
    git add '*.go'
    export GOPROXY=off SOURCE_DATE_EPOCH=1793880000
    bash build.sh --variant base --arch x86_64 --version "$taskVersion" --binary-only --output /output
    /output/build/amd64/base/sing-box version
    sha256sum /output/build/amd64/base/sing-box
    bash build.sh --variant base --arch aarch64_generic --version "$taskVersion" --binary-only --output /output
    sha256sum /output/build/arm64/base/sing-box
fi
