#!/bin/sh
# Offline, reproducible source; generated fixtures are mounted separately.
set -eu
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
taskCommit=$(sed -n 's/^commit=//p' /core/UPSTREAM | tr -d '\r')
git -c safe.directory=/source -C /source archive "$taskCommit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for patch in /core/patches/*.patch; do git apply "$patch"; done
cp /extra-tests/dns_policy_test.go dns/
cp /extra-tests/mixed_dns_test.go dns/
cp /extra-tests/dns_policy_dial_test.go cmd/sing-box/
cp /extra-tests/mixed_fakeip_test.go cmd/sing-box/
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -run 'TestKabanmaxGeneratedDNS|TestDomainOnlyRuleTakesSubnetOnlyRuleSet' ./dns ./cmd/sing-box
