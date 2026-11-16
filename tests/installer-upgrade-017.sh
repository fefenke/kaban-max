#!/usr/bin/env bash
# Installer decision functions only: no package manager, network or device changes.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
source <(sed -n '/^decide_kabanmax() {/,/^}/p' "$repo/install.sh")
source <(sed -n '/^decide_core() {/,/^}/p' "$repo/install.sh")
uci() { printf 'ru\n'; }
vercmp() { case "$1/$2" in 0.1.6/0.1.7|1.14.4-r11/1.14.4-r12) printf -- '-1\n';; *) printf '0\n';; esac; }
info() { :; }
t() { :; }
check_compatible() { test "$RESULT_KABANMAX/$RESULT_CORE" = '0.1.7/1.14.4-r12'; }
for variant in base tiny; do
    KABANMAX_OLD=0.1.6 APP_OLD=0.1.6 I18N_OLD=0.1.6 I18N=1
    FORK_URL='' TARGET_TAG=0.1.7 F_VERSION=0.1.7 F_CORE_MIN=1.14.4-r10
    CORE_OLD=1.14.4-r11 CORE_OLD_VARIANT="$variant" C_VERSION=1.14.4-r12
    VARIANT='' ASK_VARIANT=0 CORE_ACTION=none CORE_REINSTALL=0
    NEED_KABANMAX=0 NEED_APP=0 NEED_I18N=0
    decide_kabanmax
    decide_core
    test "$NEED_KABANMAX/$NEED_APP/$NEED_I18N" = 1/1/1
    test "$CORE_ACTION/$RESULT_VARIANT" = "install/$variant"
done
printf '0.1.6/r11 -> 0.1.7/r12 selects backend, UI, RU and matching base/tiny core: OK\n'
