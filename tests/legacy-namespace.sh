#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
source <(sed -n '/^legacy_migrate() {/,/^}/p' "$repo/install.sh")
source <(sed -n '/^legacy_finish() {/,/^}/p' "$repo/install.sh")
source <(sed -n '/^legacy_restore() {/,/^}/p' "$repo/install.sh")
source <(sed -n '/^finish() {/,/^}/p' "$repo/install.sh")
log() { :; }
detail() { :; }
t() { :; }
contains() { return 0; }
cleanup() { :; }
BACKUP='' LOG=/dev/null
LEGACY_ROOT="$work" LEGACY_MIGRATED=0
mkdir -p "$work/etc/config" "$work/etc/forkop/lists" "$work/opt/forkop-zapret2/releases/vtest"
printf '%s\n' "config settings 'settings'" "option config_version '2.0.0'" "list rule_set '/etc/forkop/lists/rocketleague.lst'" "option nfqws2_opt '--lua-init=@/opt/forkop-zapret2/current/lua/custom.lua'" > "$work/etc/config/forkop"
printf '%s\n' '203.0.113.0/24' > "$work/etc/forkop/lists/rocketleague.lst"
printf '%s\n' '{"section_1":1}' > "$work/etc/forkop/zapret2-slots.json"
ln -s releases/vtest "$work/opt/forkop-zapret2/current"
legacy_migrate
test "$LEGACY_MIGRATED" = 1
grep -q /etc/kabanmax/lists/rocketleague.lst "$work/etc/config/kabanmax"
grep -q /opt/kabanmax-zapret2/current/lua/custom.lua "$work/etc/config/kabanmax"
cmp "$work/etc/forkop/lists/rocketleague.lst" "$work/etc/kabanmax/lists/rocketleague.lst"
cmp "$work/etc/forkop/zapret2-slots.json" "$work/etc/kabanmax/zapret2-slots.json"
test -e "$work/opt/kabanmax-zapret2/current"
test -e "$work/opt/forkop-zapret2/current"
printf '%s\n' 'interrupted package defaults' > "$work/etc/config/kabanmax"
LEGACY_MIGRATED=0
legacy_migrate
grep -q /etc/kabanmax/lists/rocketleague.lst "$work/etc/config/kabanmax"
printf '%s\n' 'package defaults' > "$work/etc/config/kabanmax"
set +e
(finish 3 transaction)
failed_status=$?
set -e
test "$failed_status" = 3
grep -q /etc/kabanmax/lists/rocketleague.lst "$work/etc/config/kabanmax"
legacy_restore
grep -q /etc/kabanmax/lists/rocketleague.lst "$work/etc/config/kabanmax"
printf '%s\n' 'new user settings' > "$work/etc/config/kabanmax"
LEGACY_MIGRATED=0
legacy_migrate
test "$LEGACY_MIGRATED" = 1
grep -q 'new user settings' "$work/etc/config/kabanmax"
printf '%s\n' 'package defaults' > "$work/etc/config/kabanmax"
legacy_restore
grep -q 'new user settings' "$work/etc/config/kabanmax"
legacy_finish
test ! -e "$work/etc/config/forkop"
test ! -e "$work/etc/forkop"
test ! -L "$work/opt/forkop-zapret2"
test -e "$work/opt/kabanmax-zapret2/current"
echo 'Legacy namespace migration preserves configuration, list bytes, slots and engine assets: OK'
