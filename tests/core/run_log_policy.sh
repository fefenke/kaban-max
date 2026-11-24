#!/bin/sh
set -eu
# Read-only project + pinned Git object; no router/VPS/network probes.
sourceRepo=${1:-/source}
project=${2:-/work}
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
commit=$(sed -n 's/^commit=//p' "$project/core/UPSTREAM" | tr -d '\r')
git -c safe.directory="$sourceRepo" -C "$sourceRepo" archive "$commit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for patch in "$project"/core/patches/*.patch; do git apply --check "$patch"; git apply "$patch"; done
cp "$project/tests/core/connection_log_policy_test.go" route/
cp "$project/tests/core/dns_log_policy_test.go" dns/
cp "$project/tests/core/lifecycle_log_test.go" log/
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./route ./dns ./protocol/group ./log
GOPROXY=off CGO_ENABLED=0 go build -trimpath -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -o "$taskTmp/lifecycle-core" ./cmd/sing-box
python3 "$project/tests/core/lifecycle_log_binary.py" "$taskTmp/lifecycle-core"
