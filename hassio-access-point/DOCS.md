# Hass.io Access Point

Use your Home Assistant host as a WiFi access point.

## Configuration

### Options
- **ssid** (**required**): The name of your access point
- **wpa_passphrase** (**required**): The passkey for your access point (8 to 63 characters)
- **channel** (**required**): The WiFi channel to use: 1-14 in 2.4GHz, 36-165 in 5GHz (36, 40, 44, 48 recommended, DFS channels 52-144 are often unsupported in AP mode)
- **address** (**required**): The address of your hass.io WiFi card/network
- **netmask** (**required**): Subnet mask of the network
- **broadcast** (*optional*): Broadcast address of the network. Computed from `address` and `netmask` if empty
- **interface** (*optional*): Which wlan card to use. Default: wlan0
- **hide_ssid** (*optional*): Hide the SSID. `true` = hidden. Defaults to `false`
- **dhcp** (*optional*): Enable the DHCP server. Defaults to `false`
- **dhcp_start_addr** (*optional*): Start address for DHCP range. Required if DHCP enabled
- **dhcp_end_addr** (*optional*): End address for DHCP range. Required if DHCP enabled
- **allow_mac_addresses** (*optional*): List of MAC addresses to allow. Note: if using allow, blocks everything not in list
- **deny_mac_addresses** (*optional*): List of MAC addresses to block. Note: if using deny, allows everything not in list
- **band** (*optional*): `2.4GHz` (default) or `5GHz`. In 5GHz the addon enables 802.11n/ac and uses 80 MHz when the channel allows it (set `ht_capab: '[HT20]'` for 20 MHz only). Devices that only support 2.4 GHz will not see the network
- **country_code** (*optional*): Two-letter ISO country code (e.g. `FR`) for the WiFi regulatory domain
- **ap_isolate** (*optional*): Prevent WiFi clients from talking to each other. Defaults to `false`
- **dhcp_lease_time** (*optional*): DHCP lease duration (`30m`, `12h`, `2d`, `1w`, `infinite`). Defaults to `12h`
- **debug** (*optional*): Set logging level. 0 = basic output, 1 = show addon detail and every DHCP exchange, 2 = same as 1 plus run hostapd in debug mode
- **ht_capab** (*optional*): Set WiFi adapter's HT capabilities. Defaults to `[HT40][SHORT-GI-20][DSSS_CCK-40]`
- **hostapd_config_override** (*optional*): List of hostapd config options to add to hostapd.conf (can be used to override existing options)
- **client_internet_access** (*optional*): Provide internet access for clients. `true` = enable. Defaults to `false`
- **client_dns_override** (*optional*): Specify list of DNS servers for clients. Requires DHCP to be enabled. Note: Add-on will try to use DNS servers of the parent host by default.
- **dnsmasq_config_override** (*optional*): List of dnsmasq config options to add to dnsmasq.conf (can be used to override existing options, as well as reserving IPs, e.g. `dhcp-host=12:34:56:78:90:AB,192.168.99.123`)

Note: use either allow or deny lists for MAC filtering. If using allow, deny will be ignored.

### Example configuration

```yaml
ssid: AP-NAME
wpa_passphrase: AP-PASSWORD
channel: 6
address: 192.168.10.1
netmask: 255.255.255.0
interface: wlan0
hide_ssid: true
dhcp: true
dhcp_start_addr: 192.168.10.10
dhcp_end_addr: 192.168.10.20
allow_mac_addresses: []
deny_mac_addresses:
  - "ab:cd:ef:fe:dc:ba"
band: 2.4GHz
country_code: FR
ap_isolate: false
dhcp_lease_time: 12h
debug: 0
hostapd_config_override: []
client_internet_access: true
client_dns_override:
  - 1.1.1.1
  - 8.8.8.8
```

### Troubleshooting

- **`Interface wlan0 not found`**: the log lists the wireless interfaces the addon can see. Set `interface` to one of them.
- **5GHz network not visible**: the device may be 2.4 GHz only, or the channel is DFS. Try channel 36, 40, 44 or 48 with `country_code` set.
- **`does not report AP mode support`**: the WiFi chip/driver cannot act as an access point. Use another adapter.
- **Addon stops right after start**: the log says which daemon exited (hostapd or dnsmasq). Set `debug: 2` for hostapd details.
- **Clients connect but get no IP**: enable `debug: 1`, every DHCP exchange (`DHCPDISCOVER`, `DHCPOFFER`, `DHCPACK`) is then logged.
- **Clients have an IP but no internet**: check `client_internet_access: true` and that the host has a default route. The log warns when `net.ipv4.ip_forward` is 0.
- **DHCP leases** are stored in `/data/dnsmasq.leases` and survive restarts.
