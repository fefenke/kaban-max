#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for fn in fetch enough_ram pause_for_ram resume_for_ram; do
 source <(sed -n "/^$fn() {/,/^}/p" "$repo/install.sh")
done
WORK=$(mktemp -d);trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/log";KABANMAX_RUNNING=1;EARLY_STOPPED=0;STARTED=0;stopped=0;started=0
log(){ :; };step(){ :; };warn(){ :; };t(){ printf '%s' "$1"; };mb(){ echo "$1"; };fail(){ return 1; };arm_memory_recovery(){ :; }
deadline(){ case "${*: -1}" in stop) stopped=1;; start) started=1;; esac; }
mem_available_kb(){ if [ "$stopped" = 1 ];then echo 80000;else echo 19000;fi; };free_kb(){ echo 100000; }
enough_ram 20480 downloads
test "$stopped/$EARLY_STOPPED" = 1/1
resume_for_ram
test "$started/$EARLY_STOPPED" = 1/0
# An HTTP403 is not necessarily a quota error; preserve retryable network failure.
wget(){ printf '%s\n' "$answer" >&2;return 8; }
answer='HTTP error403: Forbidden';status=0;fetch https://api.github.com/test "$WORK/out" || status=$?;test "$status" = 4
answer='HTTP error429: Too Many Requests';status=0;fetch https://api.github.com/test "$WORK/out" || status=$?;test "$status" = 3
wget(){ case "$*" in *rate_limit*) return 0;; *) printf '%s\n' 'HTTP error403' >&2;return 8;; esac; }
jsonfilter(){ echo 0; }
status=0;fetch https://api.github.com/test "$WORK/out" || status=$?;test "$status" = 3
# finish must actually restore the service on pre-transaction failure.
source <(sed -n '/^finish() {/,/^}/p' "$repo/install.sh")
contains(){ return 0; };detail(){ :; };cleanup(){ :; };BACKUP=''
EARLY_STOPPED=1;STARTED=0
deadline(){ touch "$WORK/restarted"; }
if (finish 1 network);then exit 1;fi
test -f "$WORK/restarted"
echo 'Installer RAM recovery and403/429 classification: PASS'
