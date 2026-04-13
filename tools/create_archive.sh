#!/system/bin/sh
#
# create_rootfs_archive.sh - Create a portable tarball of the Alpine rootfs
# Uses the same mounting logic as mount_alpine.sh
#
# Usage: ./create_rootfs_archive.sh

set -e

# --- Configuration ----------------------------------------------------------
IMG="/data/local/pivot/alpine_aarch64.img"
MNT="/data/local/pivot/alpine"
OUTPUT="/sdcard/alpine-rootfs.tar.gz"

# Log to console only (no file to avoid permission issues)
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

error_exit() {
    log "ERROR: $*"
    exit 1
}

# --- Mount the image (exactly as in mount_alpine.sh) ------------------------
log "Starting rootfs archive creation"

# Temporarily relax SELinux to avoid mount denials
setenforce 0

# Find a free loop device
LOOP_DEV=$(losetup -f)
if [ -z "$LOOP_DEV" ]; then
    error_exit "No free loop device found!"
fi

# Associate loop device with the image
log "Setting up loop device $LOOP_DEV for $IMG"
losetup "$LOOP_DEV" "$IMG" || error_exit "Failed to set up loop device"

# Mount the image as ext4 with suid and dev
log "Mounting $LOOP_DEV to $MNT"
mount -t ext4 -o suid,dev "$LOOP_DEV" "$MNT" || {
    losetup -d "$LOOP_DEV"
    error_exit "Mount failed"
}

log "Successfully mounted $IMG on $MNT (loop: $LOOP_DEV)"

# --- Create tarball (excluding runtime/bind directories) --------------------
log "Creating archive at $OUTPUT"
cd "$MNT" || error_exit "Cannot cd to mount point"

# Use tar with --exclude for each directory that should not be part of the rootfs
tar -czf "$OUTPUT" \
    --exclude='./android_root' \
    --exclude='./mnt' \
    --exclude='./media' \
    --exclude='./lost+found' \
    . 2>/dev/null || error_exit "tar creation failed"

log "Archive created successfully: $OUTPUT"
ls -lh "$OUTPUT"

# --- Unmount the image (exactly as in umount_alpine.sh) ---------------------
log "Unmounting $MNT"
cd /  # ensure we're not inside the mount point
umount "$MNT" || error_exit "Unmount failed"

# Detach the loop device
losetup -d "$LOOP_DEV" && log "Detached $LOOP_DEV"

# Restore SELinux enforcing (optional, but keeps Android happy)
setenforce 1

log "All done. Archive is ready at $OUTPUT"
