#!/usr/bin/env bash
#
# End-to-end tests for athena (`./tests/integration.sh`).
#
# Starts a real athena-server with a stubbed journalctl/logger, inside a
# private network namespace, then asserts on the actual nftables state and on
# the CLI output. Nothing on the host firewall is touched.

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)

# Everything happens in a throwaway network namespace: nft gets a real
# CAP_NET_ADMIN there, and the host ruleset is never modified.
if [[ ${ATHENA_TEST_NETNS:-0} != 1 ]]; then
    if ! command -v unshare >/dev/null 2>&1; then
        echo "skip: unshare(1) not available"
        exit 0
    fi
    if (( EUID == 0 )); then
        export ATHENA_TEST_NETNS=1
        exec unshare --net -- "$0" "$@"
    fi
    export ATHENA_TEST_NETNS=1
    exec unshare --user --map-root-user --net -- "$0" "$@"
fi

if ! command -v nft >/dev/null 2>&1; then
    echo "skip: nft(8) not installed"
    exit 0
fi

FAILED=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/athena-test.XXXXXX")
daemon_pid=""
cleanup() {
    [[ -n $daemon_pid ]] && kill "$daemon_pid" 2>/dev/null
    nft delete table inet athena 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$work/bin" "$work/run" "$work/state"

# --- stubs ----------------------------------------------------------------
cat > "$work/bin/journalctl" <<'STUB'
#!/usr/bin/env bash
# Minimal journalctl stand-in: replays STUB_SSH_LOG for sshd queries, and
# STUB_ATHENA_LOG for `-t athena` (Athena's own events).
stream=${STUB_SSH_LOG:-/dev/null}
own=${STUB_ATHENA_LOG:-/dev/null}
follow=0
own_query=0
prev=""
for arg in "$@"; do
    [[ $arg == -f ]] && follow=1
    [[ $prev == -t && $arg == athena ]] && own_query=1
    prev=$arg
done
if (( own_query )); then
    [[ -r $own ]] && cat "$own"
    exit 0
fi
[[ -r $stream ]] && cat "$stream"
(( follow )) && sleep 3600
exit 0
STUB

cat > "$work/bin/logger" <<'STUB'
#!/usr/bin/env bash
# logger stand-in: appends "<tag>: <message>" to STUB_ATHENA_EVENTS.
tag=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -t) tag=$2; shift 2 ;;
        *) break ;;
    esac
done
printf '%s: %s\n' "$tag" "$*" >> "${STUB_ATHENA_EVENTS:-/dev/null}"
STUB

chmod +x "$work/bin/journalctl" "$work/bin/logger"

# --- fixtures -------------------------------------------------------------
cat > "$work/athena.conf" <<CONF
THRESHOLD=2
BAN_TIME=3600
FIND_TIME=600
CHECK_INTERVAL=1
WHITE_LIST="127.0.0.1 192.168.50.0/24"
PORT_BLOCK=all
CONF

: > "$work/ssh.log"
: > "$work/athena.log"

sshd_line() {   # sshd_line <ip> [suffix]
    printf 'Nov 19 13:33:37 host sshd-session[42]: Failed password for root from %s port 4444 ssh2%s\n' "$1" "${2:-}"
}

export PATH="$work/bin:$PATH"
export STUB_SSH_LOG="$work/ssh.log"
export STUB_ATHENA_LOG="$work/athena.log"
export STUB_ATHENA_EVENTS="$work/athena.log"
export ATHENA_CONF="$work/athena.conf"
export ATHENA_RUN_DIR="$work/run"
export ATHENA_STATE_DIR="$work/state"
export ATHENA_VERSION_FILE="$repo/VERSION"

start_daemon() {
    "$repo/athena-server" >> "$work/daemon.log" 2>&1 &
    daemon_pid=$!
}

stop_daemon() {
    [[ -n $daemon_pid ]] || return 0
    kill "$daemon_pid" 2>/dev/null
    wait "$daemon_pid" 2>/dev/null
    daemon_pid=""
}

banned() {   # banned <ip> [set]
    nft get element inet athena "${2:-athena_blacklist}" "{ $1 }" >/dev/null 2>&1
}

wait_for() {  # wait_for <timeout-seconds> <command...>
    local timeout=$1 i
    shift
    for (( i = 0; i < timeout * 10; i++ )); do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}

logged() { grep -qF -- "$1" "$work/athena.log"; }

# --- scenario: daemon bans a repeat offender ------------------------------
sshd_line 203.0.113.5 >> "$work/ssh.log"
start_daemon
sleep 1.5
sshd_line 203.0.113.5 >> "$work/ssh.log"
wait_for 5 banned 203.0.113.5 && pass "repeat offender banned" || fail "repeat offender banned"
logged "[BAN] 203.0.113.5" && pass "[BAN] event logged" || fail "[BAN] event logged"

# --- scenario: a single failure is below the threshold --------------------
sshd_line 198.51.100.9 >> "$work/ssh.log"
sleep 2.5
if banned 198.51.100.9; then fail "single failure must not ban"; else pass "single failure not banned"; fi

# --- scenario: whitelisted networks are never banned ----------------------
sshd_line 192.168.50.148 >> "$work/ssh.log"
sshd_line 192.168.50.148 >> "$work/ssh.log"
sshd_line 192.168.50.148 >> "$work/ssh.log"
sshd_line 127.0.0.1 >> "$work/ssh.log"
sshd_line 127.0.0.1 >> "$work/ssh.log"
sleep 2.5
if banned 192.168.50.148; then fail "whitelisted CIDR must not be banned"; else pass "whitelisted CIDR not banned"; fi
if banned 127.0.0.1; then fail "loopback must not be banned"; else pass "loopback not banned"; fi

# --- scenario: lines carrying a method suffix are still parsed ------------
sshd_line 203.0.113.8 " : RSA SHA256:abcdef" >> "$work/ssh.log"
sshd_line 203.0.113.8 " : RSA SHA256:abcdef" >> "$work/ssh.log"
wait_for 5 banned 203.0.113.8 && pass "ban with method suffix" || fail "ban with method suffix"

# --- scenario: the CLI lists and unbans ----------------------------------
( cd "$work" && "$repo/athena" -l ) > "$work/list.out" 2>&1
if grep -q '203.0.113.5' "$work/list.out"; then pass "athena -l lists banned ip"; else fail "athena -l lists banned ip"; fi
if grep -qi 'aucun\|no ban' "$work/list.out"; then fail "athena -l must not claim the set is empty"; else pass "athena -l reports a non-empty set"; fi

# The source log is cleared first: without a grace period (see the
# "manual unban is honoured" scenario) the daemon would re-ban immediately
# from the log lines still inside the finding window.
: > "$work/ssh.log"
( cd "$work" && "$repo/athena" -u 203.0.113.5 ) > "$work/unban.out" 2>&1
wait_for 5 bash -c "! nft get element inet athena athena_blacklist '{ 203.0.113.5 }' >/dev/null 2>&1" \
    && pass "athena -u removes the address" || fail "athena -u removes the address"

( cd "$work" && "$repo/athena" -u 203.0.113.99 ) > "$work/unban2.out" 2>&1
grep -qi 'not banned\|pas banni' "$work/unban2.out" && pass "athena -u on a clean address" \
    || fail "athena -u on a clean address"

( cd "$work" && "$repo/athena" -u "not-an-ip" ) > "$work/unban3.out" 2>&1
grep -qiE 'invalid|invalide' "$work/unban3.out" && pass "athena -u rejects garbage" \
    || fail "athena -u rejects garbage"

stop_daemon

# --- summary --------------------------------------------------------------
if (( FAILED )); then
    echo
    echo "---- daemon log ----"
    cat "$work/daemon.log"
    echo "--------------------"
    exit 1
fi
echo "all integration tests passed"
