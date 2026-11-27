#!/bin/sh
set -eu
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
taskCommit=$(sed -n 's/^commit=//p' /core/UPSTREAM | tr -d '\r')
git -c safe.directory=/source -C /source archive "$taskCommit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for patch in /core/patches/*.patch; do git apply "$patch"; done
git apply --check /extra-tests/ruleprovider_synchronization.patch
git apply /extra-tests/ruleprovider_synchronization.patch
cp /extra-tests/lifecycle_cold_test.go cmd/sing-box/
gofmt -w cmd/sing-box/lifecycle_cold_test.go
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -run TestLifecycle -v ./cmd/sing-box
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./dns/transport/fakeip ./experimental/clashapi ./common/urltest ./parser/subscription
# conn_test.go's three TestTLS* cases dial external 1.1.1.1; keep this offline.
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -run 'TestClientHelloRecord|TestFragment|TestIndex|TestIntegrationWait' ./common/tlsfragment
