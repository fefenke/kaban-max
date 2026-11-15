#!/usr/bin/env bash
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
source <(sed -n '/^ask_translation() {/,/^}/p' "$repo/install.sh")
source <(sed -n '/^decide_kabanmax() {/,/^}/p' "$repo/install.sh")
t() { printf '%s' "$1"; }
question_block() { :; }
log() { :; }
may_ask() { test "$INTERACTIVE" = 1; }
ask() { calls=$((calls + 1)); test "$answer" = yes; }
uci() { printf '%s' "$LUCILANG"; }
vercmp() { printf 0; }
info() { :; }
core_requirement() { :; }
pkg_depends() { :; }

for answer in yes no; do
  calls=0 INTERACTIVE=1 KABANMAX_OLD='' I18N_OLD='' I18N=0 NEED_I18N=0
  NEED_KABANMAX=0 NEED_APP=0 APP_OLD='' FORK_URL='' TARGET_TAG='' F_VERSION=1 LUCILANG=en
  decide_kabanmax
  ask_translation
  test "$calls" = 1
  if test "$answer" = yes; then test "$I18N/$NEED_I18N" = 1/1; else test "$I18N/$NEED_I18N" = 0/0; fi
done

for installed in '' 1; do
  calls=0 INTERACTIVE=1 KABANMAX_OLD=1 I18N_OLD=$installed I18N=0 NEED_I18N=0
  NEED_KABANMAX=0 NEED_APP=0 APP_OLD=1 FORK_URL='' TARGET_TAG='' F_VERSION=1 LUCILANG=ru
  decide_kabanmax
  ask_translation
  test "$calls" = 0
  if test -n "$installed"; then test "$I18N" = 1; else test "$I18N" = 0; fi
done

# An automatic LuCI language with an explicitly English installer must not
# silently opt into an additional Russian package on a noninteractive install.
calls=0 INTERACTIVE=0 KABANMAX_OLD='' I18N_OLD='' I18N=0 NEED_I18N=0
NEED_KABANMAX=0 NEED_APP=0 APP_OLD='' FORK_URL='' TARGET_TAG='' F_VERSION=1 LUCILANG=auto LANG_OPT=en
decide_kabanmax
ask_translation
test "$calls/$I18N/$NEED_I18N" = 0/0/0
for pair in 'ru en' 'auto ru'; do
  read -r LUCILANG LANG_OPT <<< "$pair"
  calls=0 INTERACTIVE=0 KABANMAX_OLD='' I18N_OLD='' I18N=0 NEED_I18N=0
  NEED_KABANMAX=0 NEED_APP=0 APP_OLD='' FORK_URL='' TARGET_TAG='' F_VERSION=1
  decide_kabanmax
  ask_translation
  if test "$LANG_OPT" = ru; then test "$I18N/$NEED_I18N" = 1/1; else test "$I18N/$NEED_I18N" = 0/0; fi
done

# Noninteractive LuCI runs do not prompt; an upgrade follows installed package state.
for installed in '' 1; do
  calls=0 INTERACTIVE=0 KABANMAX_OLD=1 I18N_OLD=$installed I18N=0 NEED_I18N=0
  NEED_KABANMAX=0 NEED_APP=0 APP_OLD=1 FORK_URL='' TARGET_TAG='' F_VERSION=1 LUCILANG=en
  decide_kabanmax
  ask_translation
  test "$calls" = 0
  if test -n "$installed"; then test "$I18N" = 1; else test "$I18N" = 0; fi
done
echo 'Translation prompt fresh yes/no and installed upgrade state: OK'
