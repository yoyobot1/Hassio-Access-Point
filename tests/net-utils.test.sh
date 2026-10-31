#!/usr/bin/env bash
# Run: bash tests/net-utils.test.sh
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=../hassio-access-point/net-utils.sh
source hassio-access-point/net-utils.sh

FAILED=0
check() {
    local name=$1 expected=$2 actual=$3
    if [ "${expected}" = "${actual}" ]; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name}: expected '${expected}', got '${actual}'"
        FAILED=1
    fi
}

check "prefix /24" 24 "$(netmask_to_prefix 255.255.255.0)"
check "prefix /22" 22 "$(netmask_to_prefix 255.255.252.0)"
check "prefix /8" 8 "$(netmask_to_prefix 255.0.0.0)"
check "prefix /25" 25 "$(netmask_to_prefix 255.255.255.128)"
check "prefix /32" 32 "$(netmask_to_prefix 255.255.255.255)"
check "prefix /0" 0 "$(netmask_to_prefix 0.0.0.0)"
netmask_to_prefix 255.0.255.0 >/dev/null; check "reject non-contiguous" 1 $?
netmask_to_prefix 255.255.255.1 >/dev/null; check "reject odd octet" 1 $?
netmask_to_prefix 255.255.253.0 >/dev/null; check "reject 253" 1 $?

check "ip round trip" 192.168.99.1 "$(int_to_ip "$(ip_to_int 192.168.99.1)")"
check "broadcast /24" 192.168.99.255 "$(broadcast_of 192.168.99.1 255.255.255.0)"
check "broadcast /22" 10.1.7.255 "$(broadcast_of 10.1.5.7 255.255.252.0)"
check "network /24" 192.168.99.0 "$(network_of 192.168.99.1 255.255.255.0)"
check "join" "a,b,c" "$(join_by_comma a b c)"

is_5ghz_channel 36; check "5GHz ch 36 valid" 0 $?
is_5ghz_channel 11; check "5GHz ch 11 invalid" 1 $?
is_5ghz_channel 37; check "5GHz ch 37 invalid" 1 $?
is_dfs_channel 52; check "52 is DFS" 0 $?
is_dfs_channel 48; check "48 not DFS" 1 $?
is_dfs_channel 149; check "149 not DFS" 1 $?
check "ht40 36" "+" "$(ht40_direction 36)"
check "ht40 40" "-" "$(ht40_direction 40)"
check "ht40 149" "+" "$(ht40_direction 149)"
check "ht40 161" "-" "$(ht40_direction 161)"
ht40_direction 165 >/dev/null; check "ht40 165 none" 1 $?
check "vht80 36" 42 "$(vht80_center 36)"
check "vht80 48" 42 "$(vht80_center 48)"
check "vht80 149" 155 "$(vht80_center 149)"
check "vht80 161" 155 "$(vht80_center 161)"
vht80_center 165 >/dev/null; check "vht80 165 none" 1 $?

exit "${FAILED}"
