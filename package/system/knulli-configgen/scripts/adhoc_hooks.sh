#!/bin/bash

CHANNEL="6"
INTERFACE=$(knulli-wifi get_interface)

SSID=$(knulli-settings-get wifi.adhoc.ssid)
PASSPHRASE=$(knulli-settings-get wifi.adhoc.key)

adhoc_flag="/tmp/.adhoc_ap_enabled"

hostapd_pid="/tmp/hostapd.pid"
hostapd_conf="/tmp/hostapd.conf"

dnsmasq_pid="/tmp/dnsmasq.pid"
dnsmasq_leases="/tmp/dnsmasq.leases"

is_quickresume_boot() {
  local code
  code="$(curl -s --max-time 0.3 -o /dev/null -w "%{http_code}" \
          "http://127.0.0.1:1234/runningGame" 2>/dev/null)"

  [ "$code" = "000" ] # api isn't running with quickresume
}

should_start_ap() {
    if [ "$(knulli-settings-get global.netplay)" != "1" ] || [ "$(knulli-settings-get global.netplay.hotspot)" != "1" ]; then
        return 1
    fi

    if is_quickresume_boot; then
        return 1
    fi

    if [ -z "$INTERFACE" ]; then
        return 1
    fi

    if ip addr show "$INTERFACE" | grep -q 'inet '; then
        return 1
    fi

    return 0
}

case $1 in
    gameStart)
        if should_start_ap; then
            touch "$adhoc_flag"

            ip link set "$INTERFACE" up
            ip addr flush dev "$INTERFACE"
            sleep 0.1
            ip addr add 192.168.4.1/24 dev "$INTERFACE"

            cat <<EOF > "$hostapd_conf"
interface=$INTERFACE
driver=nl80211
ssid=$SSID
channel=$CHANNEL
hw_mode=g
auth_algs=1
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

            hostapd "$hostapd_conf" &
            echo $! > "$hostapd_pid"

            dnsmasq --interface="$INTERFACE" \
                    --bind-interfaces \
                    --dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,12h \
                    --dhcp-leasefile="$dnsmasq_leases" \
                    --no-resolv &
            echo $! > "$dnsmasq_pid"

            for i in {1..100}; do
                if iw dev "$INTERFACE" info | grep -q "type AP"; then
                    break
                fi
                sleep 0.1
            done
        fi
        ;;
    gameStop)
        if [ -f "$adhoc_flag" ]; then
            kill "$(cat "$hostapd_pid")"
            rm -f "$hostapd_pid"

            kill "$(cat "$dnsmasq_pid")"
            rm -f "$dnsmasq_pid"
            rm -f "$dnsmasq_leases"

            ip addr flush dev "$INTERFACE"
            rm -f "$adhoc_flag"
        fi
        ;;
esac

