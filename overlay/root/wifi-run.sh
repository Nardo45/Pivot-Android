#!/bin/sh

SSID="$1"
PASS="$2"
IP="$3"
GW="$4"

# Kill any existing wpa_supplicant and clean up stale socket
pkill wpa_supplicant 2>/dev/null
rm -f /run/wpa_supplicant/wlan0

# Bring interface down, flush IPs, then up
ip link set wlan0 down 2>/dev/null
ip addr flush dev wlan0
ip link set wlan0 up

# Write wpa_supplicant config
cat <<EOC > /run/wpa_supplicant.conf
ctrl_interface=/run/wpa_supplicant
update_config=1
network={
    ssid="$SSID"
    psk="$PASS"
}
EOC

# Start wpa_supplicant in background
wpa_supplicant -B -i wlan0 -c /run/wpa_supplicant.conf

# Wait for association (timeout 30 seconds)
echo "Waiting for Wi-Fi association..."
for i in $(seq 1 30); do
    if wpa_cli -i wlan0 status | grep -q "wpa_state=COMPLETED"; then
        break
    fi
    sleep 1
done

# Check if we are associated
if ! wpa_cli -i wlan0 status | grep -q "wpa_state=COMPLETED"; then
    echo "Failed to associate with $SSID"
    exit 1
fi

echo "Associated, waiting for carrier (LOWER_UP)..."
for i in $(seq 1 10); do
    if ip link show wlan0 | grep -q "LOWER_UP"; then
        break
    fi
    sleep 1
done

# Now configure IP and routing
if [ -n "$IP" ] && [ -n "$GW" ]; then
    echo "Configuring static IP $IP/24, gateway $GW"
    ip addr add "$IP"/24 dev wlan0
else
    echo "No static config, using DHCP"
    udhcpc -i wlan0
    # After DHCP, extract gateway from route
    GW=$(ip route show | grep default | awk '{print $3}')
    IP=$(ip addr show wlan0 | grep -o 'inet [0-9.]*' | cut -d' ' -f2)
    if [ -z "$GW" ]; then
        echo "DHCP didn't set a default route"
        exit 1
    fi
fi

# ----- Android policy routing bypass -----
# Create a dedicated routing table (200) and add our routes
TABLE=200
ip route del 10.0.0.0/24 dev wlan0 table $TABLE 2>/dev/null
ip route del default dev wlan0 table $TABLE 2>/dev/null
ip route add 10.0.0.0/24 dev wlan0 table $TABLE
ip route add default via "$GW" dev wlan0 table $TABLE

# Add a high-priority rule that sends all traffic to our table
# Remove any existing rule for this table to avoid duplicates
ip rule del from all lookup $TABLE priority 1000 2>/dev/null
ip rule add from all lookup $TABLE priority 1000

# Set DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf

echo "Wi-Fi configured with static IP $IP, gateway $GW"
