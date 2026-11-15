#!/bin/sh
# Run inside the documented offline container; mounts are read-only.
set -eu
taskTmp=$(mktemp -d)
trap 'rm -rf "$taskTmp"' EXIT
taskCommit=$(sed -n 's/^commit=//p' /core/UPSTREAM | tr -d '\r')
git -c safe.directory=/source -C /source archive "$taskCommit" | tar -x -C "$taskTmp"
cd "$taskTmp"
for patch in /core/patches/*.patch; do git apply "$patch"; done
cp /extra-tests/editor_reload_test.go cmd/sing-box/
GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -run 'TestEditorReload|TestStableFingerprint|TestStableObservationReload|TestStableObservationRestoreDoesNotRestoreHealth|TestFallbackKeepsRoutedConnectionsAcrossASwitch|TestFallbackKeepsTheDialContextOfAnOpenConnection|TestStableDialOnlyAndOldStreamCannotVetoFailure' ./cmd/sing-box ./protocol/group
