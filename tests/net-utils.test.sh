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

exit "${FAILED}"
