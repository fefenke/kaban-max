#!/bin/sh
set -eu
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
taskCommit=$(sed -n 's/^commit=//p' /core/UPSTREAM | tr -d '\r')
git -c safe.directory=/source -C /source archive "$taskCommit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for patch in /core/patches/*.patch; do git apply "$patch"; done
cp /extra-tests/fingerprint_catalog_tls_test.go common/tls/
cp /extra-tests/fingerprint_catalog_parser_test.go protocol/parser/
KABANMAX_FINGERPRINT_CATALOG=/shared/tls-fingerprints.json GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -run 'TestApplicationFingerprintCatalog|TestChrome155|TestRealityFingerprintWithout|TestParser.*Fingerprint' ./common/tls ./protocol/parser
