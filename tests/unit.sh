#!/usr/bin/env bash
#
# Unit tests for the pure helpers of athena-server (`./tests/unit.sh`).
# No root, no nftables and no journal access needed.

set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../athena-server
source "$here/../athena-server"

FAILED=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=1; }

expect_ok() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

expect_nok() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

expect_eq() {
    local desc=$1 want=$2 got=$3
    if [[ $want == "$got" ]]; then
        pass "$desc"
    else
        fail "$desc (want '$want', got '$got')"
    fi
}

# --- IPv4 literals --------------------------------------------------------
expect_ok   "is_ipv4 203.0.113.5"            is_ipv4 203.0.113.5
expect_ok   "is_ipv4 0.0.0.0"                is_ipv4 0.0.0.0
expect_ok   "is_ipv4 255.255.255.255"        is_ipv4 255.255.255.255
expect_nok  "is_ipv4 256.1.1.1"              is_ipv4 256.1.1.1
expect_nok  "is_ipv4 1.2.3"                  is_ipv4 1.2.3
expect_nok  "is_ipv4 1.2.3.4.5"              is_ipv4 1.2.3.4.5
expect_nok  "is_ipv4 2001:db8::1"            is_ipv4 2001:db8::1
expect_nok  "is_ipv4 empty"                  is_ipv4 ""
expect_nok  "is_ipv4 1.2.3.4; rm -rf /"      is_ipv4 '1.2.3.4; rm -rf /'

# --- IPv6 literals --------------------------------------------------------
expect_ok   "is_ipv6 ::1"                    is_ipv6 ::1
expect_ok   "is_ipv6 ::"                     is_ipv6 ::
expect_ok   "is_ipv6 2001:db8::1"            is_ipv6 2001:db8::1
expect_ok   "is_ipv6 fe80::1"                is_ipv6 fe80::1
expect_ok   "is_ipv6 full 8 hextets"         is_ipv6 2001:0db8:0000:0000:0000:0000:0000:0001
expect_nok  "is_ipv6 1:2:3:4:5:6:7"          is_ipv6 1:2:3:4:5:6:7
expect_nok  "is_ipv6 1:2:3:4:5:6:7:8:9"      is_ipv6 1:2:3:4:5:6:7:8:9
expect_nok  "is_ipv6 1::2::3"                is_ipv6 1::2::3
expect_nok  "is_ipv6 2001:db8:zz::1"         is_ipv6 2001:db8:zz::1
expect_nok  "is_ipv6 203.0.113.5"            is_ipv6 203.0.113.5

# --- IPv4 CIDR matching ---------------------------------------------------
expect_ok   "192.168.21.5 in 192.168.21.0/24"   ip_in_cidr 192.168.21.5 192.168.21.0/24
expect_nok  "192.168.22.5 not in 192.168.21.0/24" ip_in_cidr 192.168.22.5 192.168.21.0/24
expect_ok   "10.1.2.3 in 10.0.0.0/8"            ip_in_cidr 10.1.2.3 10.0.0.0/8
expect_ok   "8.8.8.8 in 0.0.0.0/0"              ip_in_cidr 8.8.8.8 0.0.0.0/0
expect_ok   "203.0.113.5 in 203.0.113.5/32"     ip_in_cidr 203.0.113.5 203.0.113.5/32
expect_nok  "203.0.113.6 not in 203.0.113.5/32" ip_in_cidr 203.0.113.6 203.0.113.5/32
expect_nok  "172.32.0.1 not in 172.16.0.0/12"   ip_in_cidr 172.32.0.1 172.16.0.0/12
expect_nok  "invalid prefix 192.168.0.1/33"     ip_in_cidr 192.168.0.1 192.168.0.0/33
expect_ok   "plain literal matches itself"      ip_in_cidr 192.168.50.148 192.168.50.148
expect_nok  "plain literal differs"             ip_in_cidr 192.168.50.149 192.168.50.148

# --- IPv6 CIDR matching ---------------------------------------------------
expect_ok   "2001:db8::5 in 2001:db8::/32"      ip_in_cidr 2001:db8::5 2001:db8::/32
expect_nok  "2001:db9::5 not in 2001:db8::/32"  ip_in_cidr 2001:db9::5 2001:db8::/32
expect_ok   "::1 in ::1/128"                    ip_in_cidr ::1 ::1/128
expect_nok  "::2 not in ::1/128"                ip_in_cidr ::2 ::1/128
expect_ok   "fe80::1 in fe80::/10"              ip_in_cidr fe80::1 fe80::/10
expect_nok  "2001:db8::1 not in fe80::/10"      ip_in_cidr 2001:db8::1 fe80::/10
expect_ok   "2001:db8:1::1 in 2001:db8::/32"    ip_in_cidr 2001:db8:1::1 2001:db8::/32
expect_ok   "anything in ::/0"                  ip_in_cidr 2001:db8::1 ::/0
expect_ok   "literal ipv6 matches itself"       ip_in_cidr 2001:db8::1 2001:db8::1

# --- whitelist ------------------------------------------------------------
WHITE_LIST="127.0.0.1 192.168.50.0/24 ::1 2001:db8::/32"
expect_ok   "whitelist: loopback v4"            is_whitelisted 127.0.0.1
expect_ok   "whitelist: LAN v4"                 is_whitelisted 192.168.50.148
expect_ok   "whitelist: loopback v6"            is_whitelisted ::1
expect_ok   "whitelist: documented v6 prefix"   is_whitelisted 2001:db8:aa::9
expect_nok  "whitelist: public v4 not listed"   is_whitelisted 203.0.113.5
expect_nok  "whitelist: public v6 not listed"   is_whitelisted 2606:4700::1111
export WHITE_LIST=""

# --- set selection -------------------------------------------------------
expect_eq   "set_for_ip: ipv4"              athena_blacklist  "$(set_for_ip 203.0.113.5)"
expect_eq   "set_for_ip: ipv6"              athena_blacklist6 "$(set_for_ip 2001:db8::1)"
expect_nok  "set_for_ip: rejects garbage"   set_for_ip "not-an-ip"

# --- journal line parsing -------------------------------------------------
line_pw='Nov 19 13:33:37 host sshd-session[1]: Failed password for root from 203.0.113.5 port 4444 ssh2'
line_invalid='Nov 19 13:33:37 host sshd-session[1]: Failed password for invalid user admin from 203.0.113.9 port 4445 ssh2'
line_rsa='Nov 19 13:33:37 host sshd-session[1]: Failed password for root from 203.0.113.8 port 4447 ssh2: RSA SHA256:abc'
line_pubkey='Nov 19 13:33:37 host sshd-session[1]: Failed publickey for root from 203.0.113.7 port 4448 ssh2: ED25519 SHA256:xyz'
line_kbd='Nov 19 13:33:37 host sshd-session[1]: Failed keyboard-interactive/pam for root from 203.0.113.6 port 4449 ssh2'
line_v6='Nov 19 13:33:37 host sshd-session[1]: Failed password for root from 2001:db8::66 port 4450 ssh2'
line_ok='Nov 19 13:33:37 host sshd-session[1]: Accepted publickey for root from 203.0.113.5 port 2222 ssh2'
line_other='Nov 19 13:33:37 host sshd-session[1]: Connection closed by 203.0.113.5 port 3333'

expect_eq "extract_ip: password"               203.0.113.5  "$(extract_ip "$line_pw")"
expect_eq "extract_ip: invalid user"           203.0.113.9  "$(extract_ip "$line_invalid")"
expect_eq "extract_ip: method suffix"          203.0.113.8  "$(extract_ip "$line_rsa")"
expect_eq "extract_ip: publickey"              203.0.113.7  "$(extract_ip "$line_pubkey")"
expect_eq "extract_ip: keyboard-interactive"   203.0.113.6  "$(extract_ip "$line_kbd")"
expect_eq "extract_ip: ipv6 source"            2001:db8::66 "$(extract_ip "$line_v6")"
expect_eq "extract_ip: accepted line"          ""           "$(extract_ip "$line_ok")"
expect_eq "extract_ip: unrelated line"         ""           "$(extract_ip "$line_other")"

# The old awk $(NF-3) parser returned the port on lines carrying a method
# suffix; make sure the port is never mistaken for the address.
expect_nok "extract_ip: rsa suffix not read as port" test "$(extract_ip "$line_rsa")" = "4447"

# --- journalctl argument building ----------------------------------------
export SSH_LOG_TAGS="sshd sshd-session"
expect_eq "journal_args: two tags" \
    "$(printf -- '-t\nsshd\n-t\nsshd-session')" "$(journal_args)"

echo
if (( FAILED )); then
    echo "FAILED"
    exit 1
fi
echo "all unit tests passed"
