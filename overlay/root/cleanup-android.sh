#!/bin/sh
# cleanup-android.sh - Purge Android processes while preserving hardware states

MY_PID=$$
MODEM_NODE="/android_root/dev/subsys_modem"
ANDROID_PATTERN="/system/|/vendor/|/product/|/system_ext/|/odm/|/apex/|magisk|/data/adb/"

# --- Hardware Persistence Hijack (Persistent) -------------------------------
# We spawn a background process to hold the modem node open.
# This prevents hardware collapse when pm-service dies.
# Using 'sleep infinity' ensures the FD stays open for the entire uptime.
# -----------------------------------------------------------------------------
if [ -c "$MODEM_NODE" ]; then
    if ! pgrep -f "sleep infinity.*$MODEM_NODE" > /dev/null; then
        echo "[Pivot-Cleanup] Spawning persistent hardware keep-alive..."
        # Open the node for reading in a background process that ignores SIGHUP
        ( nohup sleep infinity < "$MODEM_NODE" > /dev/null 2>&1 & )
    else
        echo "[Pivot-Cleanup] Hardware keep-alive already active."
    fi
fi

for p in /proc/[0-9]*; do
    pid=${p##*/}

    # Skip PID 1, and the current script
    [ "$pid" -eq 1 ] && continue
    [ "$pid" -eq "$MY_PID" ] && continue

    cmdline=$(cat "$p/cmdline" 2>/dev/null | tr '\0' ' ')
    [ -z "$cmdline" ] && continue

    # Identify Android-space processes
    if echo "$cmdline" | grep -iqE "$ANDROID_PATTERN"; then

        # Protective exclusion for critical low-level daemons
        # We preserve vold/init to avoid kernel panic/watchdog triggers
        case "$cmdline" in
            *vold*|*init*)
                continue
                ;;
        esac

        echo "Cleaning up Android remnant: PID $pid ($cmdline)"

        kill -9 "$pid" 2>/dev/null || true
    fi
done

# Reclaim memory from purged processes
sync
echo 3 > /proc/sys/vm/drop_caches
