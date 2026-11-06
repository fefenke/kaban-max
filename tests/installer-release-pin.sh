#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed -n '/^decide_kabanmax() {/,/^}/p' "$repo/install.sh")
uci() { echo ru; }
vercmp() { echo 1; }
info() { :; }
t() { :; }
core_requirement() { echo 1.14.4-r2; }
pkg_depends() { :; }
KABANMAX_OLD=2.1.0 APP_OLD=2.1.0 I18N_OLD=2.1.0 FORK_URL=''
F_VERSION=0.1.0 TARGET_TAG=0.1.0 I18N=1
NEED_KABANMAX=0 NEED_APP=0 NEED_I18N=0
decide_kabanmax
test "$RESULT_KABANMAX" = 0.1.0
test "$NEED_KABANMAX/$NEED_APP/$NEED_I18N" = 1/1/1
echo 'Explicit release pin selects all matching application packages: OK'
