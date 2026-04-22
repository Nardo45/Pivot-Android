#!/bin/sh
# alpine-setup.sh – runs after pivot, configures Wi‑Fi, starts SSH
# Flags: -c (run cleanup), -r (run safe rebind)

set -e

# Default values (disabled unless flag is passed)
RUN_CLEANUP=false
RUN_REBIND=false

# Parse flags
while getopts "cr" opt; do
  case $opt in
    c) RUN_CLEANUP=true ;;
    r) RUN_REBIND=true ;;
    *) echo "Usage: $0 [-c] [-r]" >&2; exit 1 ;;
  esac
done

echo "=== Alpine setup starting ==="

# 1. Try to obtain native WiFi Controls
echo "Configuring Wi‑Fi..."
if [ -x /root/wifi-run.sh ]; then
    echo "Killing system_server (if running)..."
    pkill system_server 2>/dev/null || true
    /root/wifi-run.sh "SSID" "PASS" IP_ADDRESS GATEWAY_IP
else
    echo "ERROR: /root/wifi-run.sh not found or not executable"
fi

# 3. Make OpenRC happy
mkdir -p /run/openrc
touch /run/openrc/softlevel

# 4. Start SSH server
echo "Starting sshd..."
if rc-service sshd start 2>/dev/null; then
    echo "sshd started via rc-service sshd"
elif rc-service ssh start 2>/dev/null; then
    echo "sshd started via rc-service ssh"
else
    echo "rc-service failed, trying direct /usr/sbin/sshd"
    /usr/sbin/sshd
fi

# Loop until port 22 is active
echo "Waiting for sshd to bind to port 22..."
MAX_RETRIES=10
COUNT=0
while ! netstat -ltn | grep -q ":22 "; do
    sleep 1
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
        echo "sshd failed to bind in time. Proceeding anyway..."
        break
    fi
done
echo "sshd is live."

# 5. Conditional cleanup logic
if [ "$RUN_CLEANUP" = true ]; then
    if [ -x /root/cleanup-android.sh ]; then
        echo "Running cleanup-android.sh..."
        /root/cleanup-android.sh
    else
        echo "cleanup-android.sh not found, skipping"
    fi
else
    echo "Cleanup flag (-c) not set, skipping Android process cleanup"
fi

# 6. Conditional Safe Rebind Logic
if [ "$RUN_REBIND" = true ]; then
    echo "Checking for populated Android mount sources..."
    for target in dev proc sys; do
        SRC="/android_root/$target"
        DEST="/$target"

        if [ "$(ls -A "$SRC" 2>/dev/null)" ]; then
            echo "Source $SRC is populated. Safe to rbind."
            mount --rbind "$SRC" "$DEST" 2>/dev/null || echo "Failed to bind $DEST"
        else
            echo "WARNING: $SRC is empty! Skipping rbind."
            case "$target" in
                proc) mount -t proc proc /proc ;;
                sys)  mount -t sysfs sysfs /sys ;;
            esac
        fi
    done
else
    echo "Rebind flag (-r) not set, skipping Android mount rebinding"
fi

echo "=== Alpine setup complete ==="
