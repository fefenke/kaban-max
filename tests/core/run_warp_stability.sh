#!/bin/sh
# Offline focused tests on the reproducible source, never the dirty private tree.
set -eu
sourceRepo=${1:-/source}
project=${2:-/work}
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
taskCommit=$(sed -n 's/^commit=//p' "$project/core/UPSTREAM" | tr -d '\r')
git -c safe.directory="$sourceRepo" -C "$sourceRepo" archive "$taskCommit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for patch in "$project"/core/patches/*.patch; do git apply --check "$patch"; git apply "$patch"; done
git apply --check "$project/tests/core/ruleprovider_synchronization.patch"
git apply "$project/tests/core/ruleprovider_synchronization.patch"
cp "$project/tests/core/warp_stability_test.go" protocol/warp/
cp "$project/tests/core/warp_port_hint_test.go" protocol/warp/
cp "$project/tests/core/warp_paths_api_test.go" experimental/clashapi/
cp "$project/tests/core/warp_udp_recovery_test.go" transport/wireguard/
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./protocol/warp ./common/cloudflare ./transport/wireguard ./experimental/clashapi
