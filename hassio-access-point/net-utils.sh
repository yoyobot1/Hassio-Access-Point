#!/usr/bin/env bash
# Pure helpers, sourced by run.sh and covered by tests/net-utils.test.sh

# 192.168.99.1 -> integer
ip_to_int() {
    local a b c d
    IFS=. read -r a b c d <<<"$1"
    echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

# integer -> 192.168.99.1
int_to_ip() {
    local n=$1
    echo "$(( (n >> 24) & 255 )).$(( (n >> 16) & 255 )).$(( (n >> 8) & 255 )).$(( n & 255 ))"
}

# 255.255.255.0 -> 24. Returns 1 on invalid mask (non-standard octet or
# non-contiguous bits).
netmask_to_prefix() {
    local octet prefix=0 seen_partial=0
    local IFS=.
    for octet in $1; do
        if [ "${seen_partial}" -eq 1 ] && [ "${octet}" != "0" ]; then
            return 1
        fi
        case "${octet}" in
            255) prefix=$((prefix + 8)) ;;
            254) prefix=$((prefix + 7)); seen_partial=1 ;;
            252) prefix=$((prefix + 6)); seen_partial=1 ;;
            248) prefix=$((prefix + 5)); seen_partial=1 ;;
            240) prefix=$((prefix + 4)); seen_partial=1 ;;
            224) prefix=$((prefix + 3)); seen_partial=1 ;;
            192) prefix=$((prefix + 2)); seen_partial=1 ;;
            128) prefix=$((prefix + 1)); seen_partial=1 ;;
            0) seen_partial=1 ;;
            *) return 1 ;;
        esac
    done
    echo "${prefix}"
}

# a b c -> a,b,c
join_by_comma() {
    local IFS=,
    echo "$*"
}

# network address and broadcast address for ADDRESS NETMASK
network_of() {
    int_to_ip $(( $(ip_to_int "$1") & $(ip_to_int "$2") ))
}

broadcast_of() {
    local mask_int
    mask_int=$(ip_to_int "$2")
    int_to_ip $(( ($(ip_to_int "$1") & mask_int) | (~mask_int & 0xFFFFFFFF) ))
}
