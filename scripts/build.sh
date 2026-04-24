#!/bin/bash

build_and_deploy() {
    # --- Image Generation --------------------------------------------------------
    log "Building base $SELECTED_DISTRO image via Podman..."
    podman build --arch aarch64 -t "$PODMAN_BASE_TAG" -f "$SELECTED_CONTAINERFILE" .

    log "Injecting user configuration into image..."

    # Resolve the user-add command now that $NEW_USER is confirmed.
    # Expanding it here (on the host) means the Containerfile gets a literal
    # username string, no shell variable indirection inside the container RUN layer.
    if [[ "$USER_ADD_TOOL" == "adduser_alpine" ]]; then
        RESOLVED_USER_ADD="adduser -D $NEW_USER"
    else
        RESOLVED_USER_ADD="useradd -m -s /bin/bash $NEW_USER"
    fi

    cat <<EOF > .temp_dockerfile
FROM $PODMAN_BASE_TAG
ENV PIVOT_USER=$NEW_USER
COPY overlay/root/gnu-setup.sh /root/gnu-setup.sh
COPY overlay/root/wifi-run.sh /root/wifi-run.sh
RUN chmod +x /root/*.sh && \\
    sed -i 's|SSID|"$USER_SSID"|g' /root/gnu-setup.sh && \\
    sed -i 's|PASS|"$USER_PASS"|g' /root/gnu-setup.sh && \\
    sed -i 's|IP_ADDRESS|$USER_IP|g' /root/gnu-setup.sh && \\
    sed -i 's|GATEWAY_IP|$USER_GW|g' /root/gnu-setup.sh && \\
    $RESOLVED_USER_ADD && \\
    echo "$NEW_USER:$NEW_PASS" | chpasswd && \\
    echo "root:$NEW_PASS" | chpasswd
EOF

    podman build -t "$PODMAN_CFG_TAG" -f .temp_dockerfile .
    rm .temp_dockerfile

    log "Exporting rootfs to $ROOTFS_FILE..."
    CONTAINER_ID=$(podman create "$PODMAN_CFG_TAG")
    podman export "$CONTAINER_ID" | gzip > "$ROOTFS_FILE"
    podman rm "$CONTAINER_ID"
    podman rmi "$PODMAN_CFG_TAG" "$PODMAN_BASE_TAG"

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
    echo ""
    echo "Next step — run on-device to create the ${IMAGE_SIZE_HUMAN} disk image:"
    echo "  cd $TERMUX_HOME"
    echo "  ./restore_archive.sh $ROOTFS_FILE $IMAGE_SIZE_MIB"
    echo "-----------------------------------------------------------------------"
}
