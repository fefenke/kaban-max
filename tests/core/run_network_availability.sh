#!/bin/sh
set -eu
# All traffic in tests is synthetic/local. Production WAN checks are not started off OpenWrt.
sourceRepo=${1:-/source}
project=${2:-/work}
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
commit=$(sed -n 's/^commit=//p' "$project/core/UPSTREAM" | tr -d '\r')
git -c safe.directory="$sourceRepo" -C "$sourceRepo" archive "$commit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for patch in "$project"/core/patches/*.patch; do git apply --check "$patch"; git apply "$patch"; done
cp "$project/tests/core/fakeip_ipv6_guard_test.go" common/autoroute/
cp "$project/tests/core/fakeip_ipv6_migration_test.go" dns/transport/fakeip/
cp "$project/tests/core/dns_log_policy_test.go" dns/
cp "$project/tests/core/connection_log_policy_test.go" route/
cp "$project/tests/core/wan_state_test.go" "$project/tests/core/wan_probe_test.go" common/wanstate/
cp "$project/tests/core/wan_log_gate_test.go" log/
cp "$project/tests/core/lifecycle_log_test.go" log/
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute ./dns ./dns/transport/fakeip ./route ./protocol/group ./common/wanstate ./log
GOPROXY=off go test -run '^$' -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./cmd/sing-box
