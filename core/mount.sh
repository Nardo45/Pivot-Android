#!/system/bin/sh

IMG="/data/local/pivot/alpine_aarch64.img"
MNT="/data/local/pivot/alpine"

# Temporarily relax SELinux to avoid mount denials
setenforce 0

# Find a free loop device
LOOP_DEV=$(losetup -f)
if [ -z "$LOOP_DEV" ]; then
    echo "No free loop device found!"
    exit 1
fi

# Associate loop device with the image
losetup "$LOOP_DEV" "$IMG"
if [ $? -ne 0 ]; then
    echo "Failed to set up loop device $LOOP_DEV"
    exit 1
fi

# Mount the image as ext4 with suid and dev
mount -t ext4 -o suid,dev "$LOOP_DEV" "$MNT"
if [ $? -eq 0 ]; then
    echo "Successfully mounted $IMG on $MNT (loop: $LOOP_DEV)"
else
    echo "Mount failed. Cleaning up loop device..."
    losetup -d "$LOOP_DEV"
    exit 1
fi
