#!/bin/bash

# --- Configuration -----------------------------------------------------------
TERMUX_HOME="/data/data/com.termux/files/home"
IMAGE_DIR="/data/local/pivot"
LOG_PREFIX="[Pivot-Setup]"
SAVED_CONFIG_FILE=".pivot_config.enc"
CONTAINERFILES_DIR="containerfiles"

# Files to manage for installation/uninstallation (rootfs file appended after distro selection)
CORE_FILES=("pvroot.sh" "mount.sh" "umount.sh" "set_rprivate" "create_archive.sh" "restore_archive.sh")

log()        { echo "$LOG_PREFIX $*"; }
error_exit() { echo "$LOG_PREFIX ERROR: $*" >&2; exit 1; }

# --- Password Input with * Masking -------------------------------------------
# Usage: read_secret <variable_name> <prompt>
read_secret() {
    local __var="$1"
    local __prompt="$2"
    local __input=""
    local __char=""

    printf "%s" "$__prompt"
    while IFS= read -r -s -n1 __char; do
        # Enter or carriage return ends input
        if [[ -z "$__char" || "$__char" == $'\r' ]]; then
            echo ""
            break
        fi
        # Backspace support
        if [[ "$__char" == $'\x7f' || "$__char" == $'\x08' ]]; then
            if [[ -n "$__input" ]]; then
                __input="${__input%?}"
                printf "\b \b"
            fi
        else
            __input+="$__char"
            printf "*"
        fi
    done
    printf -v "$__var" '%s' "$__input"
}

# --- Config Encryption Helpers -----------------------------------------------
encrypt_config() {
    local config_data="$1"
    local passphrase="$2"
    printf '%s' "$config_data" | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
        -pass "pass:$passphrase" -out "$SAVED_CONFIG_FILE" 2>/dev/null
}

decrypt_config() {
    local passphrase="$1"
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
        -pass "pass:$passphrase" -in "$SAVED_CONFIG_FILE" 2>/dev/null
}
