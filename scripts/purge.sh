#!/bin/bash

run_purge() {
    log "Initiating system purge..."
    adb get-state > /dev/null 2>&1 || error_exit "No device connected via ADB."
    adb root > /dev/null 2>&1 && sleep 2

    log "Removing core framework files from $TERMUX_HOME..."
    for file in "${CORE_FILES[@]}"; do
        adb shell "rm -f $TERMUX_HOME/$file"
    done
    # Also remove any rootfs tarballs that may be present
    adb shell "rm -f $TERMUX_HOME/*-rootfs-aarch64.tar.gz"

    echo "-----------------------------------------------------------------------"
    echo "The directory $IMAGE_DIR contains your persistent disk image."
    read -p "Do you want to delete the persistent image and its folder? (y/N): " PURGE_IMG
    if [[ "$PURGE_IMG" =~ ^[Yy]$ ]]; then
        log "Deleting $IMAGE_DIR..."
        adb shell "rm -rf $IMAGE_DIR"
    else
        log "Skipping $IMAGE_DIR. Your data remains intact."
    fi

    if [[ -f "$SAVED_CONFIG_FILE" ]]; then
        echo "-----------------------------------------------------------------------"
        read -p "A saved configuration file was found. Delete it too? (y/N): " PURGE_CFG
        if [[ "$PURGE_CFG" =~ ^[Yy]$ ]]; then
            rm -f "$SAVED_CONFIG_FILE"
            log "Saved config deleted."
        fi
    fi

    echo "-----------------------------------------------------------------------"
    log "Purge complete."
}
