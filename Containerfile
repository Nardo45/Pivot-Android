# Use the official Alpine aarch64 base image
FROM --platform=linux/arm64/v8 alpine:latest

# Install packages for Wi-Fi, SSH server, and OpenRC
RUN apk add --no-cache \
    openrc \
    wpa_supplicant \
    openssh-server \
    iproute2 \
    util-linux

# Copy the overlay directory into the rootfs
COPY overlay/ /

# Ensure your scripts are executable
RUN chmod +x /usr/local/bin/poweroff /usr/local/bin/reboot
