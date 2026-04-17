#!/bin/bash
# Pivot-Android: Automated Rootfs Builder & Installer
set -e

# --- Configuration -----------------------------------------------------------
TERMUX_HOME="/data/data/com.termux/files/home"
ROOTFS_FILE="alpine-rootfs-aarch64.tar.gz"
LOG_PREFIX="[Pivot-Builder]"

log() { echo "$LOG_PREFIX $*"; }
error_exit() { echo "$LOG_PREFIX ERROR: $*" >&2; exit 1; }

# --- Dependency Check: Podman & QEMU -----------------------------------------
if ! command -v podman &> /dev/null; then
    error_exit "Podman is not installed. Please install it to build the rootfs."
fi

# Check for aarch64 emulation support
if ! podman run --rm --arch aarch64 alpine uname -m | grep -q "aarch64"; then
    echo "-----------------------------------------------------------------------"
    echo "ERROR: aarch64 emulation is not configured."
    echo "Podman cannot execute ARM64 binaries on this host."
    echo ""
    echo "To fix this, install the following packages for your distro:"
    echo "  Ubuntu/Debian: sudo apt install qemu-user-static binfmt-support"
    echo "  Arch: sudo pacman -S qemu-user-static-bin binfmt-support-git"
    echo "  Fedora: sudo dnf install qemu-user-static"
    echo "Then restart the binfmt service or reboot."
    echo "-----------------------------------------------------------------------"
    exit 1
fi

# --- User Configuration & Explanations ---------------------------------------
echo "-----------------------------------------------------------------------"
echo "Pivot-Android Network & User Configuration"
echo "Why this is needed: We bake these credentials into the Alpine rootfs"
echo "so that WiFi can be brought up natively and the SSH daemon can be"
echo "accessed wirelessly immediately after the pivot operation."
echo "-----------------------------------------------------------------------"

read -p "WiFi SSID: " USER_SSID
read -p "WiFi Password: " USER_PASS
read -p "Desired Static IP: " USER_IP
read -p "Gateway IP: " USER_GW
read -p "New Linux Username: " NEW_USER
read -s -p "Password for $NEW_USER: " NEW_PASS
echo "" # New line after password prompt

# --- Image Generation --------------------------------------------------------
log "Generating configured Alpine rootfs via Podman..."

# 1. Build the base image from the Containerfile
podman build --arch aarch64 -t pivot-alpine-base .

# 2. Inject credentials and create the user using a temporary build layer
# We use 'adduser -D' for non-interactive creation and 'chpasswd' for the password.
cat <<EOF > .temp_dockerfile
FROM pivot-alpine-base
# Set environment variables for the scripts to use during first boot if needed
ENV PIVOT_USER=$NEW_USER

# Copy setup scripts
COPY overlay/root/alpine-setup.sh /root/alpine-setup.sh
COPY overlay/root/wifi-run.sh /root/wifi-run.sh

# Configuration: SSID, Pass, Network, and User creation
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

# 3. Export the container filesystem to a tarball
log "Exporting rootfs to $ROOTFS_FILE..."
CONTAINER_ID=$(podman create pivot-alpine-configured)
podman export "$CONTAINER_ID" | gzip > "$ROOTFS_FILE"
podman rm "$CONTAINER_ID"

# --- Cleanup Podman Framework Images -----------------------------------------
log "Cleaning up build images..."
# We remove the pivot-specific tags but leave the library/alpine image for future builds
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

log "Pushing $ROOTFS_FILE (this may take a moment)..."
adb push "$ROOTFS_FILE" "$TERMUX_HOME/"

adb shell "chmod +x $TERMUX_HOME/*.sh $TERMUX_HOME/set_rprivate"

echo "-----------------------------------------------------------------------"
echo "Installation Successful."
echo "Rootfs: $ROOTFS_FILE is configured for $NEW_USER on $USER_SSID."
echo "Run restore_archive.sh on the device to extract."
echo "-----------------------------------------------------------------------"
