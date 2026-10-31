#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

readonly OPTIONS_FILE=/data/options.json
readonly WORKDIR=/tmp/ap
readonly HOSTAPD_CONF="${WORKDIR}/hostapd.conf"
readonly HOSTAPD_ALLOW="${WORKDIR}/hostapd.allow"
readonly HOSTAPD_DENY="${WORKDIR}/hostapd.deny"
readonly DNSMASQ_CONF="${WORKDIR}/dnsmasq.conf"
readonly IPT=iptables-nft
readonly RULE_COMMENT=ap-addon-inet

HOSTAPD_PID=""
DNSMASQ_PID=""
CLEANED=0

DEBUG=$(bashio::config 'debug')

# Log helper. level 0 = always, 1 = addon detail (debug>=1)
log() {
    local level=$1
    shift
    if [ "${DEBUG}" -ge "${level}" ]; then
        echo "$*"
    fi
}

# Read a list option, one element per line, empty lines dropped
config_list() {
    jq -r --arg k "$1" '.[$k][]? | select(. != null and . != "")' "${OPTIONS_FILE}"
}

# Read an optional scalar option: empty string when unset or null
opt() {
    jq -r --arg k "$1" '.[$k] // empty' "${OPTIONS_FILE}"
}

flag() {
    if bashio::config.true "$1"; then echo 1; else echo 0; fi
}

ip_to_int() {
    local a b c d
    IFS=. read -r a b c d <<<"$1"
    echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

int_to_ip() {
    local n=$1
    echo "$(( (n >> 24) & 255 )).$(( (n >> 16) & 255 )).$(( (n >> 8) & 255 )).$(( n & 255 ))"
}

# 255.255.255.0 -> 24. Returns 1 on invalid mask.
netmask_to_prefix() {
    local octet prefix=0
    local IFS=.
    for octet in $1; do
        case "${octet}" in
            255) prefix=$((prefix + 8)) ;;
            254) prefix=$((prefix + 7)) ;;
            252) prefix=$((prefix + 6)) ;;
            248) prefix=$((prefix + 5)) ;;
            240) prefix=$((prefix + 4)) ;;
            224) prefix=$((prefix + 3)) ;;
            192) prefix=$((prefix + 2)) ;;
            128) prefix=$((prefix + 1)) ;;
            0) ;;
            *) return 1 ;;
        esac
    done
    echo "${prefix}"
}

join_by_comma() {
    local IFS=,
    echo "$*"
}

# Remove every iptables rule created by this addon (idempotent)
flush_ap_rules() {
    local rule
    while read -r rule; do
        # shellcheck disable=SC2086
        ${IPT} ${rule} 2>/dev/null
    done < <(${IPT} -S FORWARD 2>/dev/null | grep -- "${RULE_COMMENT}" | sed 's/^-A /-D /')
    while read -r rule; do
        # shellcheck disable=SC2086
        ${IPT} -t nat ${rule} 2>/dev/null
    done < <(${IPT} -t nat -S POSTROUTING 2>/dev/null | grep -- "${RULE_COMMENT}" | sed 's/^-A /-D /')
}

cleanup() {
    if [ "${CLEANED}" -eq 1 ]; then
        return
    fi
    CLEANED=1
    log 0 "Stopping Hass.io Access Point"
    [ -n "${HOSTAPD_PID}" ] && kill "${HOSTAPD_PID}" 2>/dev/null
    [ -n "${DNSMASQ_PID}" ] && kill "${DNSMASQ_PID}" 2>/dev/null
    wait 2>/dev/null
    flush_ap_rules
    ip addr flush dev "${INTERFACE}" 2>/dev/null
    ip link set "${INTERFACE}" down 2>/dev/null
}

trap 'cleanup; exit 0' SIGTERM SIGINT

###############################################################################
# Read and validate config
###############################################################################

for required_var in ssid wpa_passphrase channel address netmask; do
    bashio::config.require "${required_var}" "An AP cannot be created without this information"
done

SSID=$(bashio::config 'ssid')
WPA_PASSPHRASE=$(bashio::config 'wpa_passphrase')
CHANNEL=$(bashio::config 'channel')
ADDRESS=$(bashio::config 'address')
NETMASK=$(bashio::config 'netmask')
BROADCAST=$(opt broadcast)
INTERFACE=$(opt interface)
INTERFACE=${INTERFACE:-wlan0}
HIDE_SSID=$(flag hide_ssid)
DHCP_START_ADDR=$(bashio::config 'dhcp_start_addr')
DHCP_END_ADDR=$(bashio::config 'dhcp_end_addr')
HT_CAPAB=$(opt ht_capab)
HT_CAPAB=${HT_CAPAB:-[HT40][SHORT-GI-20][DSSS_CCK-40]}
COUNTRY_CODE=$(opt country_code)

if [ "${#WPA_PASSPHRASE}" -lt 8 ] || [ "${#WPA_PASSPHRASE}" -gt 63 ]; then
    bashio::exit.nok "The WPA password must be between 8 and 63 characters long!"
fi

if ! PREFIX=$(netmask_to_prefix "${NETMASK}"); then
    bashio::exit.nok "Invalid netmask: ${NETMASK}"
fi

ADDRESS_INT=$(ip_to_int "${ADDRESS}")
MASK_INT=$(ip_to_int "${NETMASK}")
NETWORK_INT=$(( ADDRESS_INT & MASK_INT ))
COMPUTED_BROADCAST=$(int_to_ip $(( NETWORK_INT | (~MASK_INT & 0xFFFFFFFF) )))

if [ -z "${BROADCAST}" ]; then
    BROADCAST=${COMPUTED_BROADCAST}
elif [ "${BROADCAST}" != "${COMPUTED_BROADCAST}" ]; then
    bashio::log.warning "Configured broadcast ${BROADCAST} differs from computed ${COMPUTED_BROADCAST} for ${ADDRESS}/${PREFIX}"
fi

if bashio::config.true 'dhcp'; then
    START_INT=$(ip_to_int "${DHCP_START_ADDR}")
    END_INT=$(ip_to_int "${DHCP_END_ADDR}")
    if [ "$(( START_INT & MASK_INT ))" -ne "${NETWORK_INT}" ] || [ "$(( END_INT & MASK_INT ))" -ne "${NETWORK_INT}" ]; then
        bashio::exit.nok "DHCP range ${DHCP_START_ADDR}-${DHCP_END_ADDR} is outside the subnet ${ADDRESS}/${PREFIX}"
    fi
    if [ "${START_INT}" -gt "${END_INT}" ]; then
        bashio::exit.nok "DHCP start address must be lower than the end address"
    fi
    if [ "${ADDRESS_INT}" -ge "${START_INT}" ] && [ "${ADDRESS_INT}" -le "${END_INT}" ]; then
        bashio::log.warning "Host address ${ADDRESS} is inside the DHCP range"
    fi
fi

if ! ip link show "${INTERFACE}" >/dev/null 2>&1; then
    bashio::log.error "Interface ${INTERFACE} not found. Available wireless interfaces:"
    iw dev | awk '$1 == "Interface" { print "  " $2 }'
    bashio::exit.nok "Set the 'interface' option to one of the above"
fi

echo "Starting Hass.io Access Point Addon"

###############################################################################
# Interface
###############################################################################

log 1 "# Setup interface ${INTERFACE}: ${ADDRESS}/${PREFIX} broadcast ${BROADCAST}"
nmcli dev set "${INTERFACE}" managed no
ip link set "${INTERFACE}" down
ip addr flush dev "${INTERFACE}"
ip addr add "${ADDRESS}/${PREFIX}" broadcast "${BROADCAST}" dev "${INTERFACE}"
ip link set "${INTERFACE}" up

###############################################################################
# hostapd.conf (regenerated on every start from the static base)
###############################################################################

mkdir -p "${WORKDIR}"
cp /hostapd.conf "${HOSTAPD_CONF}"
cp /dnsmasq.conf "${DNSMASQ_CONF}"

{
    echo ""
    echo "interface=${INTERFACE}"
    echo "ssid=${SSID}"
    echo "wpa_passphrase=${WPA_PASSPHRASE}"
    echo "channel=${CHANNEL}"
    echo "ignore_broadcast_ssid=${HIDE_SSID}"
    echo "ht_capab=${HT_CAPAB}"
} >>"${HOSTAPD_CONF}"

log 1 "# Setup hostapd: ssid=${SSID} wpa_passphrase=******** channel=${CHANNEL} ignore_broadcast_ssid=${HIDE_SSID} ht_capab=${HT_CAPAB}"

if [ -n "${COUNTRY_CODE}" ]; then
    printf 'country_code=%s\nieee80211d=1\n' "${COUNTRY_CODE}" >>"${HOSTAPD_CONF}"
    log 1 "Add to hostapd.conf: country_code=${COUNTRY_CODE}"
fi

### MAC address filtering
## Allow is more restrictive, so it takes priority (macaddr_acl=1)
mapfile -t ALLOWED < <(config_list allow_mac_addresses)
mapfile -t DENIED < <(config_list deny_mac_addresses)

if [ "${#ALLOWED[@]}" -ge 1 ]; then
    printf '%s\n' "${ALLOWED[@]}" >"${HOSTAPD_ALLOW}"
    printf 'macaddr_acl=1\naccept_mac_file=%s\n' "${HOSTAPD_ALLOW}" >>"${HOSTAPD_CONF}"
    log 0 "Allowed MAC addresses:"
    printf '%s\n' "${ALLOWED[@]}"
elif [ "${#DENIED[@]}" -ge 1 ]; then
    printf '%s\n' "${DENIED[@]}" >"${HOSTAPD_DENY}"
    printf 'macaddr_acl=0\ndeny_mac_file=%s\n' "${HOSTAPD_DENY}" >>"${HOSTAPD_CONF}"
    log 0 "Denied MAC addresses:"
    printf '%s\n' "${DENIED[@]}"
else
    echo "macaddr_acl=0" >>"${HOSTAPD_CONF}"
fi

# Append override options (later entries take precedence)
mapfile -t HOSTAPD_OVERRIDES < <(config_list hostapd_config_override)
if [ "${#HOSTAPD_OVERRIDES[@]}" -ge 1 ]; then
    log 0 "# Custom hostapd config options:"
    for override in "${HOSTAPD_OVERRIDES[@]}"; do
        echo "${override}" >>"${HOSTAPD_CONF}"
        log 0 "Add to hostapd.conf: ${override}"
    done
fi

###############################################################################
# dnsmasq.conf
###############################################################################

if bashio::config.true 'dhcp'; then
    log 1 "# DHCP enabled. Setup dnsmasq: dhcp-range=${DHCP_START_ADDR},${DHCP_END_ADDR},12h"
    {
        echo "dhcp-range=${DHCP_START_ADDR},${DHCP_END_ADDR},12h"
        echo "interface=${INTERFACE}"
    } >>"${DNSMASQ_CONF}"

    mapfile -t DNS_SERVERS < <(config_list client_dns_override)
    if [ "${#DNS_SERVERS[@]}" -eq 0 ]; then
        mapfile -t DNS_SERVERS < <(nmcli device show 2>/dev/null | awk '/IP4.DNS/ { print $2 }' | awk '!seen[$0]++')
    fi
    if [ "${#DNS_SERVERS[@]}" -eq 0 ]; then
        log 0 "Couldn't get DNS servers from host. Consider setting with 'client_dns_override' config option."
    else
        echo "dhcp-option=6,$(join_by_comma "${DNS_SERVERS[@]}")" >>"${DNSMASQ_CONF}"
        log 0 "DNS servers for clients: $(join_by_comma "${DNS_SERVERS[@]}")"
    fi

    mapfile -t DNSMASQ_OVERRIDES < <(config_list dnsmasq_config_override)
    if [ "${#DNSMASQ_OVERRIDES[@]}" -ge 1 ]; then
        log 0 "# Custom dnsmasq config options:"
        for override in "${DNSMASQ_OVERRIDES[@]}"; do
            echo "${override}" >>"${DNSMASQ_CONF}"
            log 0 "Add to dnsmasq.conf: ${override}"
        done
    fi
else
    log 1 "# DHCP not enabled. Skipping dnsmasq"
fi

###############################################################################
# Client internet access (NAT)
###############################################################################

# Always start from a clean state: removes stale rules, even after an
# interface change or an unclean stop
flush_ap_rules

if bashio::config.true 'client_internet_access'; then
    DEFAULT_ROUTE_INTERFACE=$(ip route show default | awk '/^default/ { print $5; exit }')
    if [ -z "${DEFAULT_ROUTE_INTERFACE}" ]; then
        bashio::log.error "No default route found, client internet access disabled"
    else
        log 1 "# Client internet access via ${DEFAULT_ROUTE_INTERFACE}"
        ${IPT} -t nat -A POSTROUTING -o "${DEFAULT_ROUTE_INTERFACE}" -j MASQUERADE -m comment --comment "${RULE_COMMENT}"
        ${IPT} -A FORWARD -i "${INTERFACE}" -o "${DEFAULT_ROUTE_INTERFACE}" -j ACCEPT -m comment --comment "${RULE_COMMENT}"
        ${IPT} -A FORWARD -i "${DEFAULT_ROUTE_INTERFACE}" -o "${INTERFACE}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT -m comment --comment "${RULE_COMMENT}"
        if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]; then
            bashio::log.warning "net.ipv4.ip_forward is 0 on the host, clients will have no internet access"
        fi
    fi
fi

###############################################################################
# Start daemons
###############################################################################

if bashio::config.true 'dhcp'; then
    log 1 "## Starting dnsmasq daemon"
    dnsmasq -k -C "${DNSMASQ_CONF}" &
    DNSMASQ_PID=$!
fi

log 1 "## Starting hostapd daemon"
# If debug level is greater than 1, start hostapd in debug mode
if [ "${DEBUG}" -gt 1 ]; then
    hostapd -d "${HOSTAPD_CONF}" &
else
    hostapd "${HOSTAPD_CONF}" &
fi
HOSTAPD_PID=$!

# Exit as soon as one daemon dies, so the Supervisor shows the failure
# instead of leaving a half-working AP
wait -n "${HOSTAPD_PID}" ${DNSMASQ_PID:+"${DNSMASQ_PID}"}
STATUS=$?
bashio::log.error "A daemon exited (status ${STATUS}), stopping addon"
cleanup
exit "${STATUS}"
