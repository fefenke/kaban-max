#!/bin/sh
set -eu
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
taskCommit=$(sed -n 's/^commit=//p' /core/UPSTREAM | tr -d '\r')
git -c safe.directory=/source -C /source archive "$taskCommit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for p in /core/patches/*.patch; do git apply --check "$p"; git apply "$p"; done
git apply --check /extra-tests/ruleprovider_synchronization.patch
git apply /extra-tests/ruleprovider_synchronization.patch
mkdir -p common/autoroute
cp /extra-tests/auto_routing_test.go common/autoroute/
cp /extra-tests/auto_web_test.go common/autoroute/
cp /extra-tests/auto_registry_test.go common/autoroute/
cp /extra-tests/auto_repair_test.go common/autoroute/
cp /extra-tests/auto_ip_failure_test.go common/autoroute/
cp /extra-tests/auto_dial_isolation_test.go common/autoroute/
cp /extra-tests/auto_timeout_test.go common/autoroute/
cp /extra-tests/auto_storage_test.go common/autoroute/
cp /extra-tests/auto_decision_retention_test.go common/autoroute/
cp /extra-tests/auto_source_failure_test.go common/autoroute/
cp /extra-tests/warp_udp_recovery_test.go transport/wireguard/
cp /extra-tests/auto_scope_encoding_test.go common/autoroute/
cp /extra-tests/auto_manual_test.go common/autoroute/
cp /extra-tests/auto_original_context_test.go common/autoroute/
cp /extra-tests/auto_ip_registry_test.go common/autoroute/
cp /extra-tests/auto_field_regression_test.go common/autoroute/
cp /extra-tests/auto_quic_field_test.go common/autoroute/
cp /extra-tests/auto_all_ports_test.go common/autoroute/
cp /extra-tests/auto_section_ip_test.go common/autoroute/
cp /extra-tests/auto_applied_diagnostics_test.go common/autoroute/
cp /extra-tests/auto_failed_retry_test.go common/autoroute/
cp /extra-tests/auto_probe_timeout_test.go common/autoroute/
cp /extra-tests/auto_protocol_risk_test.go common/autoroute/
cp /extra-tests/auto_late_dns_test.go common/autoroute/
cp /extra-tests/auto_ja3_alpn_test.go common/ja3/
cp /extra-tests/auto_sniff_alpn_test.go common/sniff/
cp /extra-tests/auto_dns_identity_test.go route/
cp /extra-tests/auto_fakeip_identity_test.go route/
cp /extra-tests/connections_snapshot_test.go experimental/clashapi/
cp /extra-tests/connection_log_policy_test.go route/
cp /extra-tests/dns_log_policy_test.go dns/
cp /extra-tests/fakeip_ipv6_guard_test.go common/autoroute/
cp /extra-tests/fakeip_ipv6_migration_test.go dns/transport/fakeip/
cp /extra-tests/wan_state_test.go /extra-tests/wan_probe_test.go common/wanstate/
cp /extra-tests/wan_log_gate_test.go log/
cp /extra-tests/lifecycle_log_test.go log/
cp /extra-tests/runtime_log_levels_test.go log/
cp /extra-tests/fallback_partial_failure_test.go protocol/group/
cp /extra-tests/fallback_stream_failure_test.go protocol/group/
cp /extra-tests/fallback_probe_budget_test.go protocol/group/
taskVersion=$(sed -n 's/^package_version=//p' /core/UPSTREAM | tr -d '\r')
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute ./route ./dns ./dns/transport/fakeip ./common/wanstate ./log ./experimental/clashapi ./protocol/group ./transport/wireguard ./protocol/warp ./protocol/wireguard ./experimental/cachefile ./common/ja3 ./common/sniff
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
