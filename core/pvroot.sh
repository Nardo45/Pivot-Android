#!/system/bin/sh

IMG="/data/local/pivot/alpine_aarch64.img"
MNT="/data/local/pivot/alpine"
# ↓ Uncomment this line if you are using the python script ↓
#PY="/data/data/com.termux/files/usr/bin/python3"

# 1. Kill shared propagation so pivot_root is allowed
# If the set_rprivate program is not built
# for your arch yet, you can use this python script instead.
#$PY -c 'import ctypes; libc = ctypes.CDLL("libc.so"); libc.mount(None, b"/", None, 278528, None)'
/data/data/com.termux/files/home/set_rprivate

# 2. Mount the image with full permissions
# Temporarily relax SELinux for the mount handshake
setenforce 0

# Find the first truly free loop device
LOOP_DEV=$(losetup -f)

# Associate and Mount explicitly
losetup "$LOOP_DEV" "$IMG"
if mount -t ext4 -o suid,dev "$LOOP_DEV" "$MNT"; then
    echo "Successfully mounted $IMG on $LOOP_DEV"
else
    echo "Mount failed. Checking dmesg..."
    dmesg | tail -n 10
    exit 1
fi

# 3. Bind essential kernel/hardware filesystems into the Alpine tree BEFORE pivoting
mkdir -p "$MNT/proc"
mkdir -p "$MNT/sys"
mkdir -p "$MNT/vendor"
mkdir -p "$MNT/lib/firmware/qcom"

mount --bind /proc "$MNT/proc"
mount --bind /sys "$MNT/sys"
mount --bind /vendor "$MNT/vendor"

# Bind only the GPU firmware blob directory into the place the kernel expects
mount --bind /vendor/firmware_mnt/image "$MNT/lib/firmware/qcom"

# 4. Pivot Root
cd "$MNT"
mkdir -p android_root
if ! pivot_root . android_root; then
    echo "Pivot failed! Staying in Android."
    exit 1
fi

# 5. The Handover
exec /bin/sh -c "
    # Move Android mounts out of the way for the new system
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    export HOME=/root
    export TERM=xterm-256color

    # Mount a fresh devtmpfs (this is the critical fix)
    mount -t devtmpfs none /dev

    # Setup Linux runtime environment
    mount -t devpts devpts /dev/pts
    mount -t tmpfs tmpfs /run
    mount -t tmpfs tmpfs /tmp

    # --- Run Alpine automatic setup ---
    if [ -x /root/alpine-setup.sh ]; then
        # setsid: breaks the bond with the ADB terminal/session
        # &: puts it in the background immediately
        # >/dev/null 2>&1: prevents background noise from cluttering your shell
        setsid /root/alpine-setup.sh >/tmp/start.log 2>&1 &
        echo 'Alpine background setup started (Wi-Fi/SSH)...'
    else
        echo 'alpine-setup.sh not found, skipping.'
    fi

    # Final drop into interactive Alpine bash
    exec /bin/sh -l
"
