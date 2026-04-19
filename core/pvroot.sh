#!/system/bin/sh

IMG="/data/local/pivot/alpine_aarch64.img"
MNT="/data/local/pivot/alpine"
# Path to the C-based mount propagation utility
SETPRIVATE="/data/data/com.termux/files/home/set_rprivate"

# Parse arguments
DEBUG_ADB=false
for arg in "$@"; do
    if [ "$arg" = "--adb" ]; then
        DEBUG_ADB=true
    fi
done

# 1. Resolve Mount Propagation
# pivot_root requires the root filesystem to have private propagation
# to prevent mount events from leaking into the parent namespace.
if [ -f "$SETPRIVATE" ]; then
    $SETPRIVATE
else
    # Fallback to Python if binary is missing
    /data/data/com.termux/files/usr/bin/python3 -c 'import ctypes; libc = ctypes.CDLL("libc.so"); libc.mount(None, b"/", None, 278528, None)'
fi

# 2. Prepare Loop Device and Filesystem
# Relax SELinux temporarily to permit the cross-namespace mount
setenforce 0

# Find the first truly free loop device
LOOP_DEV=$(losetup -f)

# Associate and Mount explicitly
losetup "$LOOP_DEV" "$IMG"

if mount -t ext4 -o suid,dev "$LOOP_DEV" "$MNT"; then
    echo "Successfully mounted $IMG on $LOOP_DEV"
else
    echo "Mount failure. Check dmesg for filesystem errors."
    dmesg | tail -n 10
    exit 1
fi

# 3. Hardware and Kernel Node Bridging
# Bind essential kernel filesystems into the target root tree before pivoting.
mkdir -p "$MNT/proc" "$MNT/sys" "$MNT/dev" "$MNT/lib/firmware/qcom"

mount --bind /proc "$MNT/proc"
mount --bind /sys "$MNT/sys"

# Bind only the GPU firmware blob directory into the place the kernel expects
mount --bind /vendor/firmware_mnt/image "$MNT/lib/firmware/qcom"

# Check if kernel supports devtmpfs. If not, we must bind Android's /dev
# BEFORE pivoting, otherwise we lose access to the device nodes.
HAS_DEVTMPFS=$(grep -q "devtmpfs" /proc/filesystems && echo true || echo false)

if [ "$HAS_DEVTMPFS" = "false" ]; then
    echo "Kernel lacks devtmpfs support. Bind-mounting Android /dev for hardware access."
    mount --bind /dev "$MNT/dev"
fi

# 4. Userspace Takeover (pivot_root)
cd "$MNT"
mkdir -p android_root
if ! pivot_root . android_root; then
    echo "Takeover failed. Reverting to Android userspace."
    exit 1
fi

# 5. Handover Execution
# Transition to the new root environment and initialize basic Linux VFS.
exec /bin/sh -c "
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    export HOME=/root
    export TERM=xterm-256color

    # Initialize standard Linux /dev structure only if devtmpfs is available
    if [ \"$HAS_DEVTMPFS\" = \"true\" ]; then
        # Mount a fresh devtmpfs (this is the critical fix for native Linux)
        mount -t devtmpfs none /dev
        mkdir -p /dev/pts /dev/shm
        mount -t devpts devpts /dev/pts
        mount -t tmpfs tmpfs /dev/shm
    else
        # If we bound Android's /dev, ensure pts and shm exist.
        # Android usually mounts these already, so we use mountpoint -q as a guard.
        mountpoint -q /dev/pts || mount -t devpts devpts /dev/pts
        mountpoint -q /dev/shm || mount -t tmpfs tmpfs /dev/shm
    fi

    # Setup Linux runtime environment
    mount -t tmpfs tmpfs /run
    mount -t tmpfs tmpfs /tmp

    # --- Alpine Initialization Logic ---
    if [ \"$DEBUG_ADB\" = true ]; then
        echo '--- DEBUG MODE ACTIVE ---'
        echo 'ADB flag detected. Skipping automated setup to maintain host process state.'
        echo 'WARNING: Do not disconnect this session until debugging is complete.'
    elif [ -x /root/alpine-setup.sh ]; then
        # Break the bond with the parent session to allow background service bring-up
        # setsid: breaks the bond with the ADB terminal/session
        # &: puts it in the background immediately
        # >/tmp/start.log 2>&1: prevents background noise from cluttering your shell
        setsid /root/alpine-setup.sh -c -r >/tmp/start.log 2>&1 &
        echo 'Alpine background setup initialized (Network/SSH)...'
    else
        echo 'alpine-setup.sh not found. Proceeding with manual configuration.'
    fi

    # Drop into the native Alpine shell
    exec /bin/sh -l
"
