#!/bin/sh
# alpine-setup.sh – runs after pivot, configures Wi‑Fi, starts SSH, then cleans up Android
# and remounts recursively

set -e

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

# 3. Make OpenRC happy (even though it's not PID 1)
mkdir -p /run/openrc
touch /run/openrc/softlevel

# 4. Start SSH server
echo "Starting sshd..."
# Try OpenRC service first, fall back to direct binary
if rc-service sshd start 2>/dev/null; then
    echo "sshd started via rc-service"
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

# 5. Run cleanup script to kill remaining Android processes
if [ -x /root/cleanup-android.sh ]; then
    echo "Running cleanup-android.sh..."
    /root/cleanup-android.sh
else
    echo "cleanup-android.sh not found, skipping"
fi

# 6. Safe Rebind Logic
echo "Checking for populated Android mount sources..."

for target in dev proc sys vendor; do
    SRC="/android_root/$target"
    DEST="/$target"

    # Check if the source directory has more than just . and ..
    if [ "$(ls -A "$SRC" 2>/dev/null)" ]; then
        echo "Source $SRC is populated. Safe to rbind."
        mount --rbind "$SRC" "$DEST" 2>/dev/null || echo "Failed to bind $DEST"
    else
        echo "WARNING: $SRC is empty! Skipping rbind to prevent system breakage."
        
        # Fallback: If sys/proc are empty, mount fresh instances 
        # to ensure Alpine has kernel interface access (CPU/Cgroups)
        case "$target" in
            proc) mount -t proc proc /proc ;;
            sys)  mount -t sysfs sysfs /sys ;;
        esac
    fi
done

echo "=== Alpine setup complete ==="
