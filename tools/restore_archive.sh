#!/system/bin/sh
#
# restore_rootfs_archive.sh - Restore a rootfs tarball into an Alpine image
#
# Usage: ./restore_rootfs_archive.sh [OPTIONS] <TARBALL> [SIZE_MB]
#
# Options:
#   -i IMAGE     Path to the image file (default: /data/local/pivot/alpine_aarch64.img)
#   -m MOUNTPOINT  Mount point for the image (default: /data/local/pivot/alpine)
#   -s SIZE_MB  Size of the image in MiB (only used when creating a new image)
#   -h          Show this help
#
# If the image doesn't exist, it will be created with the specified size (or prompted).
# The tarball must be a .tar.gz file created by create_rootfs_archive.sh.

set -e

# --- Defaults ---------------------------------------------------------------
IMAGE="/data/local/pivot/alpine_aarch64.img"
MOUNT_POINT="/data/local/pivot/alpine"
SIZE_MB=""
TARBALL=""

# --- Parse arguments --------------------------------------------------------
while getopts "i:m:s:h" opt; do
    case $opt in
        i) IMAGE="$OPTARG" ;;
        m) MOUNT_POINT="$OPTARG" ;;
        s) SIZE_MB="$OPTARG" ;;
        h) cat <<EOF; exit 0 ;;
Usage: $0 [OPTIONS] <TARBALL> [SIZE_MB]

Restore a rootfs tarball into an Alpine image.

If the image does not exist, it will be created with the specified size.
If no size is given and the image is missing, an error is shown.

Positional arguments:
  TARBALL                Path to the .tar.gz rootfs archive
  SIZE_MB                Size of the new image in MB (optional if image exists)

Options:
  -i IMAGE               Path to the image file (default: $IMAGE)
  -m MOUNTPOINT          Mount point for the image (default: $MOUNT_POINT)
  -s SIZE_MB             Size of the image in MB (overrides positional)
  -h                     Show this help

Examples:
  $0 -i my.img -m /mnt/alpine alpine-rootfs.tar.gz 4096
  $0 -s 8192 /sdcard/backup.tar.gz
EOF
        *) echo "Use -h for help"; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# Positional arguments: tarball and optional size
if [ -n "$1" ]; then
    TARBALL="$1"
    shift
fi
if [ -n "$1" ] && [ -z "$SIZE_MB" ]; then
    SIZE_MB="$1"
fi

# --- Validate ---------------------------------------------------------------
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"; }
error_exit() { log "ERROR: $*"; exit 1; }

if [ -z "$TARBALL" ]; then
    error_exit "No tarball specified. Usage: $0 <tarball.tar.gz> [size_mb]"
fi

# Convert relative path to absolute (works with busybox)
case "$TARBALL" in
    /*) TARBALL_ABS="$TARBALL" ;;
    *) TARBALL_ABS="$(cd "$(dirname "$TARBALL")" && pwd)/$(basename "$TARBALL")" ;;
esac
if [ ! -f "$TARBALL_ABS" ]; then
    error_exit "Tarball not found: $TARBALL_ABS"
fi

# --- Ensure parent directory for image exists -------------------------------
IMAGE_DIR=$(dirname "$IMAGE")
if [ ! -d "$IMAGE_DIR" ]; then
    log "Creating directory $IMAGE_DIR"
    mkdir -p "$IMAGE_DIR" || error_exit "Failed to create image directory"
fi

# --- Handle image creation if missing ---------------------------------------
if [ ! -f "$IMAGE" ]; then
    if [ -z "$SIZE_MB" ]; then
        error_exit "Image $IMAGE does not exist and no size provided. Use -s SIZE_MB or pass size as second argument."
    fi
    log "Creating image $IMAGE of size ${SIZE_MB}MB"
    truncate -s "${SIZE_MB}M" "$IMAGE" || error_exit "Failed to create image file"
    
    log "Formatting $IMAGE as ext4"
    mkfs.ext4 -F "$IMAGE" || error_exit "mkfs.ext4 failed"
    log "Image created and formatted"
fi

# --- Mount the image --------------------------------------------------------
log "Mounting image $IMAGE to $MOUNT_POINT"
setenforce 0

mkdir -p "$MOUNT_POINT" || error_exit "Cannot create mount point"

LOOP_DEV=$(losetup -f)
[ -z "$LOOP_DEV" ] && error_exit "No free loop device"
losetup "$LOOP_DEV" "$IMAGE" || error_exit "losetup failed"
mount -t ext4 -o suid,dev "$LOOP_DEV" "$MOUNT_POINT" || {
    losetup -d "$LOOP_DEV"
    error_exit "Mount failed"
}
log "Mounted $LOOP_DEV on $MOUNT_POINT"

# --- Extract tarball --------------------------------------------------------
log "Extracting $TARBALL_ABS into $MOUNT_POINT"

cd "$MOUNT_POINT" || error_exit "Cannot cd to mount point"

# Clean the mount point (remove everything except lost+found)
find . -mindepth 1 ! -name lost+found -exec rm -rf {} + 2>/dev/null || true

# Extract tarball (absolute path works even after cd)
tar -xzf "$TARBALL_ABS" || error_exit "tar extraction failed"

log "Extraction completed"

# --- Unmount and detach -----------------------------------------------------
cd /
umount -d "$MOUNT_POINT" || error_exit "Unmount failed"
setenforce 1

log "Restore finished. Image is ready at $IMAGE"
