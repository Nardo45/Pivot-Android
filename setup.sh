#!/bin/bash
# Pivot-Android: Automated Rootfs Builder, Installer, and Uninstaller
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/scripts/common.sh"
source "$SCRIPT_DIR/scripts/deps.sh"
source "$SCRIPT_DIR/scripts/purge.sh"
source "$SCRIPT_DIR/scripts/distro.sh"
source "$SCRIPT_DIR/scripts/image_config.sh"
source "$SCRIPT_DIR/scripts/user_config.sh"
source "$SCRIPT_DIR/scripts/build.sh"

check_openssl

if [[ "${1:-}" == "--purge" ]]; then
    run_purge
    exit 0
fi

check_podman
check_aarch64_emulation
select_distro
configure_image_size
load_or_collect_user_config
show_build_summary
build_and_deploy
