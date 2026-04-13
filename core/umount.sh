#!/system/bin/sh

MNT="/data/local/pivot/alpine"

# Unmount the image
umount "$MNT"
if [ $? -ne 0 ]; then
    echo "Unmount failed. Is the image mounted?"
    exit 1
fi

# Find which loop device was associated with the mount point
LOOP_DEV=$(losetup -l | grep "$MNT" | awk '{print $1}')
if [ -n "$LOOP_DEV" ]; then
    losetup -d "$LOOP_DEV"
    echo "Detached $LOOP_DEV"
else
    echo "No loop device found for $MNT (maybe already detached)"
fi

setenforce 1

echo "Alpine image unmounted."
