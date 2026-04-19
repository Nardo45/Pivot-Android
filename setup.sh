#!/bin/bash
# Pivot-Android: Automated Rootfs Builder, Installer, and Uninstaller
set -e

# --- Configuration -----------------------------------------------------------
TERMUX_HOME="/data/data/com.termux/files/home"
ROOTFS_FILE="alpine-rootfs-aarch64.tar.gz"
IMAGE_DIR="/data/local/pivot"
LOG_PREFIX="[Pivot-Setup]"

# Files to manage for installation/uninstallation
CORE_FILES=("pvroot.sh" "mount.sh" "umount.sh" "set_rprivate" "create_archive.sh" "restore_archive.sh" "$ROOTFS_FILE")

log() { echo "$LOG_PREFIX $*"; }
error_exit() { echo "$LOG_PREFIX ERROR: $*" >&2; exit 1; }

# --- Purge Logic -------------------------------------------------------------
if [[ "$1" == "--purge" ]]; then
    log "Initiating system purge..."
    adb get-state > /dev/null 2>&1 || error_exit "No device connected via ADB."
    adb root > /dev/null 2>&1 && sleep 2

    log "Removing core framework files from $TERMUX_HOME..."
    for file in "${CORE_FILES[@]}"; do
        adb shell "rm -f $TERMUX_HOME/$file"
    done

    echo "-----------------------------------------------------------------------"
    echo "The directory $IMAGE_DIR contains your persistent Alpine disk image."
    read -p "Do you want to delete the persistent image and its folder? (y/N): " PURGE_IMG
    if [[ "$PURGE_IMG" =~ ^[Yy]$ ]]; then
        log "Deleting $IMAGE_DIR..."
        adb shell "rm -rf $IMAGE_DIR"
    else
        log "Skipping $IMAGE_DIR. Your data remains intact."
    fi
    echo "-----------------------------------------------------------------------"
    log "Purge complete."
    exit 0
fi

# --- Dependency Check: Podman & QEMU -----------------------------------------
if ! command -v podman &> /dev/null; then
    error_exit "Podman is not installed. Please install it to build the rootfs."
fi

if ! podman run --rm --arch aarch64 alpine uname -m | grep -q "aarch64"; then
    echo "ERROR: aarch64 emulation is not configured."
    exit 1
fi

# --- User Configuration & Explanations ---------------------------------------
echo "-----------------------------------------------------------------------"
echo "Pivot-Android Network & User Configuration"
echo "-----------------------------------------------------------------------"
read -p "WiFi SSID: " USER_SSID
read -p "WiFi Password: " USER_PASS
read -p "Desired Static IP: " USER_IP
read -p "Gateway IP: " USER_GW
read -p "New Linux Username: " NEW_USER
read -s -p "Password for $NEW_USER: " NEW_PASS
echo ""

# --- Image Generation --------------------------------------------------------
log "Generating configured Alpine rootfs via Podman..."
podman build --arch aarch64 -t pivot-alpine-base .

cat <<EOF > .temp_dockerfile
FROM pivot-alpine-base
ENV PIVOT_USER=$NEW_USER
COPY overlay/root/alpine-setup.sh /root/alpine-setup.sh
COPY overlay/root/wifi-run.sh /root/wifi-run.sh
RUN chmod +x /root/*.sh && \\
    sed -i 's|SSID|"$USER_SSID"|g' /root/alpine-setup.sh && \\
    sed -i 's|PASS|"$USER_PASS"|g' /root/alpine-setup.sh && \\
    sed -i 's|IP_ADDRESS|$USER_IP|g' /root/alpine-setup.sh && \\
    sed -i 's|GATEWAY_IP|$USER_GW|g' /root/alpine-setup.sh && \\
    adduser -D "$NEW_USER" && \\
    echo "$NEW_USER:$NEW_PASS" | chpasswd && \\
    echo "root:$NEW_PASS" | chpasswd
EOF

podman build -t pivot-alpine-configured -f .temp_dockerfile .
rm .temp_dockerfile

log "Exporting rootfs to $ROOTFS_FILE..."
CONTAINER_ID=$(podman create pivot-alpine-configured)
podman export "$CONTAINER_ID" | gzip > "$ROOTFS_FILE"
podman rm "$CONTAINER_ID"
podman rmi pivot-alpine-configured pivot-alpine-base

# --- Deployment --------------------------------------------------------------
log "Verifying ADB connection..."
adb get-state > /dev/null 2>&1 || error_exit "No device connected via ADB."

log "Pushing core framework and configured rootfs..."
adb root > /dev/null 2>&1 && sleep 2

adb push core/pvroot.sh "$TERMUX_HOME/"
adb push core/mount.sh "$TERMUX_HOME/"
adb push core/umount.sh "$TERMUX_HOME/"
adb push core/bin/set_rprivate "$TERMUX_HOME/"
adb push tools/create_archive.sh "$TERMUX_HOME/"
adb push tools/restore_archive.sh "$TERMUX_HOME/"
adb push "$ROOTFS_FILE" "$TERMUX_HOME/"

adb shell "chmod +x $TERMUX_HOME/*.sh $TERMUX_HOME/set_rprivate"

echo "-----------------------------------------------------------------------"
echo "Installation Successful."
echo "-----------------------------------------------------------------------"
