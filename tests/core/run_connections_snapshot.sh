#!/bin/sh
set -eu
# Local synthetic tests; SOURCE must contain the pinned upstream Git object.
sourceRepo=${1:-/source}
project=${2:-/work}
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
commit=$(sed -n 's/^commit=//p' "$project/core/UPSTREAM" | tr -d '\r')
git -c safe.directory="$sourceRepo" -C "$sourceRepo" archive "$commit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for patch in "$project"/core/patches/*.patch; do git apply --check "$patch"; git apply "$patch"; done
git apply --check "$project/tests/core/ruleprovider_synchronization.patch"
git apply "$project/tests/core/ruleprovider_synchronization.patch"
cp "$project/tests/core/connections_snapshot_test.go" experimental/clashapi/
gofmt -w experimental/clashapi/connections_bounded.go experimental/clashapi/connections_snapshot_test.go common/trafficcontrol/manager.go experimental/clashapi/connections.go
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./experimental/clashapi ./common/trafficcontrol
GOPROXY=off go test -run '^$' -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./cmd/sing-box
