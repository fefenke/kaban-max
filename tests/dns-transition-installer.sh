#!/usr/bin/env bash
# Exercise the real install transaction with shell commands replaced by local fakes.
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
sed '/^main "\$@"$/d' "$project/install.sh" >"$scratch/functions.sh"
for scenario in success ram_paused guard_failed transaction_failed start_failed; do
    events="$scratch/$scenario.events"
    kernel_guard="$scratch/$scenario.guard"
    set +e
    (
        # shellcheck disable=SC1091
        source "$scratch/functions.sh"
        WORK="$scratch/$scenario"
        LOG="$scratch/$scenario.log"
        LOCKED=0
        mkdir -p "$WORK/new/usr/lib/kabanmax/nft"
        touch "$WORK/new/usr/lib/kabanmax/nft/dns_transition.uc"
        record() { printf '%s\n' "$1" >>"$events"; }
        log() { :; }
        fail() { record failed; cleanup; exit "$1"; }
        backup_config() { record backup; }
        install_dependencies() { record dependencies; }
        ucode() {
            record guard
            [ "$scenario" != guard_failed ] || return 1
            touch "$kernel_guard"
        }
        nft() {
            if [ "$1" = list ]; then test -f "$kernel_guard"; return; fi
            test "$1" = delete || return 1
            rm -f "$kernel_guard"
            record unguard
        }
        stop_services() { record stop; }
        legacy_migrate() { record migrate; }
        remove_files() { record remove; }
        predelete_core() { record predelete; }
        step() { :; }
        transaction() {
            record transaction
            [ "$scenario" != transaction_failed ] || fail 3 package failed
        }
        legacy_restore() { :; }
        clean_up_after() { record clean; rm -rf -- "$WORK/new"; }
        start_kabanmax() {
            record start
            [ "$scenario" != start_failed ] || fail 4 start failed
            STARTED=1
        }
        legacy_finish() { record legacy; }
        summary() { record summary; }
        if [ "$scenario" = ram_paused ]; then
            KABANMAX_RUNNING=1 EARLY_STOPPED=0
            arm_memory_recovery() { record watchdog; touch "$WORK/resume-service"; }
            deadline() { record early-stop; }
            pause_for_ram
        fi
        apply
        if [ "$scenario" = ram_paused ]; then resume_for_ram; fi
        cleanup
    )
    status=$?
    set -e
    test ! -e "$kernel_guard"
    case "$scenario" in
    success)
        test "$status" = 0
        expected=$'backup\ndependencies\nguard\nstop\nmigrate\nremove\npredelete\ntransaction\nclean\nstart\nunguard\nlegacy\nsummary'
        test "$(cat "$events")" = "$expected"
        ;;
    guard_failed)
        test "$status" = 1
        ! grep -qx stop "$events"
        ;;
    ram_paused)
        test "$status" = 0
        test "$(grep -c '^guard$' "$events")" = 1
        test "$(grep -c '^unguard$' "$events")" = 1
        test "$(head -n 3 "$events")" = $'guard\nwatchdog\nearly-stop'
        ;;
    transaction_failed) test "$status" = 3; grep -qx unguard "$events" ;;
    start_failed) test "$status" = 4; grep -qx unguard "$events" ;;
    esac
done
TEST_SOURCE="$scratch/functions.sh" TEST_WORK="$scratch/owner-exit" TEST_RECOVERED="$scratch/recovered" bash -c '
    source "$TEST_SOURCE"
    WORK="$TEST_WORK" LOG=/dev/null DNS_TRANSITION_GUARD=1
    mkdir -p "$WORK"
    log() { :; }
    nft() { touch "$TEST_RECOVERED"; }
    arm_dns_transition_recovery
'
for _ in {1..50}; do
    test ! -e "$scratch/recovered" || break
    sleep 0.1
done
test -f "$scratch/recovered"
test ! -f "$scratch/owner-exit/dns-transition"
TEST_SOURCE="$scratch/functions.sh" TEST_WORK="$scratch/work-reset" bash -c '
    source "$TEST_SOURCE"
    WORK="$TEST_WORK" LOG=/dev/null DNS_TRANSITION_GUARD=1
    mkdir -p "$WORK"
    log() { :; }
    nft() { return 0; }
    arm_dns_transition_recovery
    WORK=""
    dns_transition_stop
    test ! -e "$TEST_WORK/dns-transition"
'
if command -v busybox >/dev/null 2>&1; then
    mkdir -p "$scratch/payload/usr/lib/kabanmax/config" "$scratch/outer"
    printf 'fixture\n' >"$scratch/payload/usr/lib/kabanmax/config/migration.uc"
    tar -czf "$scratch/outer/data.tar.gz" -C "$scratch/payload" .
    for member in data.tar.gz ./data.tar.gz; do
        package="$scratch/$(printf '%s' "$member" | tr / _).ipk"
        tar -czf "$package" -C "$scratch/outer" "$member"
        TEST_SOURCE="$scratch/functions.sh" TEST_WORK="$scratch/extract-$RANDOM" TEST_PACKAGE="$package" bash -c '
            source "$TEST_SOURCE"
            WORK="$TEST_WORK" LOG=/dev/null EXT=ipk FILE_KABANMAX="$TEST_PACKAGE"
            mkdir -p "$WORK"
            tar() { busybox tar "$@"; }
            extract_new_backend || exit 1
            test -f "$WORK/new/usr/lib/kabanmax/config/migration.uc"
            test -f "$WORK/backend-extracted"
        '
    done
    printf 'BusyBox IPK extraction with both archive member names: PASS\n'
fi
printf 'DNS transition ordering and failure cleanup: PASS\n'
