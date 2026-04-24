#!/bin/bash

check_openssl() {
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. It is required for config encryption."
    fi
}

check_podman() {
    if ! command -v podman &> /dev/null; then
        error_exit "Podman is not installed. Please install it to build the rootfs."
    fi
}

check_aarch64_emulation() {
    if ! podman run --rm --arch aarch64 alpine uname -m 2>/dev/null | grep -q "aarch64"; then
        echo "ERROR: aarch64 emulation is not configured."
        exit 1
    fi
}
