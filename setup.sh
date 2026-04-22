#!/bin/bash
# Pivot-Android: Automated Rootfs Builder, Installer, and Uninstaller
set -e

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

# --- Dependency Check: openssl -----------------------------------------------
if ! command -v openssl &> /dev/null; then
    error_exit "openssl is not installed. It is required for config encryption."
fi

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

# --- Purge Logic -------------------------------------------------------------
if [[ "$1" == "--purge" ]]; then
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
    exit 0
fi

# --- Dependency Check: Podman & QEMU -----------------------------------------
if ! command -v podman &> /dev/null; then
    error_exit "Podman is not installed. Please install it to build the rootfs."
fi

if ! podman run --rm --arch aarch64 alpine uname -m 2>/dev/null | grep -q "aarch64"; then
    echo "ERROR: aarch64 emulation is not configured."
    exit 1
fi

# --- Distro Selection --------------------------------------------------------
echo "-----------------------------------------------------------------------"
echo "Pivot-Android Distro Selection"
echo "-----------------------------------------------------------------------"

if [[ ! -d "$CONTAINERFILES_DIR" ]]; then
    error_exit "Containerfiles directory '$CONTAINERFILES_DIR' not found."
fi

# Build an array of distro names by stripping the .Containerfile suffix
DISTRO_LIST=()
while IFS= read -r -d '' cfile; do
    basename=$(basename "$cfile")
    distro_name="${basename%.Containerfile}"
    DISTRO_LIST+=("$distro_name")
done < <(find "$CONTAINERFILES_DIR" -maxdepth 1 -name "*.Containerfile" -print0 | sort -z)

if [[ "${#DISTRO_LIST[@]}" -eq 0 ]]; then
    error_exit "No Containerfiles found in '$CONTAINERFILES_DIR'."
fi

echo "Available distributions:"
for i in "${!DISTRO_LIST[@]}"; do
    printf "  %d) %s\n" $(( i + 1 )) "${DISTRO_LIST[$i]}"
done
echo ""

while true; do
    read -p "Select a distro [1-${#DISTRO_LIST[@]}]: " DISTRO_CHOICE
    if [[ "$DISTRO_CHOICE" =~ ^[0-9]+$ ]] && \
       [[ "$DISTRO_CHOICE" -ge 1 ]] && \
       [[ "$DISTRO_CHOICE" -le "${#DISTRO_LIST[@]}" ]]; then
        SELECTED_DISTRO="${DISTRO_LIST[$(( DISTRO_CHOICE - 1 ))]}"
        SELECTED_CONTAINERFILE="$CONTAINERFILES_DIR/${SELECTED_DISTRO}.Containerfile"
        break
    else
        echo "  Error: Please enter a number between 1 and ${#DISTRO_LIST[@]}."
    fi
done

# Derive distro-specific variables
ROOTFS_FILE="${SELECTED_DISTRO}-rootfs-aarch64.tar.gz"
PODMAN_BASE_TAG="pivot-${SELECTED_DISTRO}-base"
PODMAN_CFG_TAG="pivot-${SELECTED_DISTRO}-configured"

# Determine the correct user-add tool for the distro.
# The actual command string is built later once $NEW_USER is known.
case "$SELECTED_DISTRO" in
    alpine)
        USER_ADD_TOOL="adduser_alpine"
        ;;
    debian|ubuntu|fedora|arch)
        USER_ADD_TOOL="useradd_standard"
        ;;
    *)
        log "Warning: Unknown distro '$SELECTED_DISTRO'. Defaulting to useradd."
        USER_ADD_TOOL="useradd_standard"
        ;;
esac

log "Selected: $SELECTED_DISTRO  |  Containerfile: $SELECTED_CONTAINERFILE"

# --- Disk Image Size Configuration -------------------------------------------
echo ""
echo "-----------------------------------------------------------------------"
echo "Pivot-Android Disk Image Configuration"
echo "-----------------------------------------------------------------------"
echo "The rootfs will live inside a sparse disk image on the device."
echo "Specify the size with a suffix: G for GiB, M for MiB."
echo "Examples: 8G = 8 GiB, 512M = 512 MiB  (minimum recommended: 2G)"
echo ""

while true; do
    read -p "Image size: " IMAGE_SIZE_INPUT
    IMAGE_SIZE_INPUT="${IMAGE_SIZE_INPUT// /}"

    if [[ "$IMAGE_SIZE_INPUT" =~ ^([0-9]+)([GgMm])$ ]]; then
        SIZE_NUM="${BASH_REMATCH[1]}"
        SIZE_UNIT="${BASH_REMATCH[2]^^}"

        if [[ "$SIZE_NUM" -eq 0 ]]; then
            echo "  Error: Size must be greater than 0. Please try again."
            continue
        fi

        if [[ "$SIZE_UNIT" == "G" ]]; then
            IMAGE_SIZE_MIB=$(( SIZE_NUM * 1024 ))
            IMAGE_SIZE_HUMAN="${SIZE_NUM} GiB"
        else
            IMAGE_SIZE_MIB="$SIZE_NUM"
            IMAGE_SIZE_HUMAN="${SIZE_NUM} MiB"
        fi

        echo "  Image size set to: $IMAGE_SIZE_HUMAN (${IMAGE_SIZE_MIB} MiB)"
        break
    else
        echo "  Error: Invalid format. Use a number followed by G or M (e.g. 8G, 512M)."
    fi
done

# --- User Configuration: Load or Collect -------------------------------------
echo ""
echo "-----------------------------------------------------------------------"
echo "Pivot-Android Network & User Configuration"
echo "-----------------------------------------------------------------------"

# Track whether the config came from the saved file so we skip the save prompt
CONFIG_FROM_FILE=false
CONFIG_CONFIRMED=false

if [[ -f "$SAVED_CONFIG_FILE" ]]; then
    echo "A saved configuration was found ($SAVED_CONFIG_FILE)."
    read -p "Load it? (Y/n): " LOAD_CHOICE
    if [[ ! "$LOAD_CHOICE" =~ ^[Nn]$ ]]; then
        read_secret CFG_PASSPHRASE "Enter config passphrase: "
        DECRYPTED=$(decrypt_config "$CFG_PASSPHRASE") || true

        if [[ -z "$DECRYPTED" ]]; then
            echo "  Error: Decryption failed. Wrong passphrase or corrupted file."
            echo "  Falling through to manual entry."
        else
            while IFS='=' read -r key value; do
                [[ -z "$key" || "$key" == \#* ]] && continue
                printf -v "$key" '%s' "$value"
            done <<< "$DECRYPTED"

            echo ""
            echo "  Loaded configuration:"
            echo "    WiFi SSID       : $USER_SSID"
            echo "    WiFi Password   : ********"
            echo "    Static IP       : $USER_IP"
            echo "    Gateway IP      : $USER_GW"
            echo "    Linux Username  : $NEW_USER"
            echo "    Linux Password  : ********"
            echo ""
            read -p "Use this configuration? (Y/n): " USE_LOADED
            if [[ ! "$USE_LOADED" =~ ^[Nn]$ ]]; then
                CONFIG_CONFIRMED=true
                CONFIG_FROM_FILE=true
            else
                echo "  Discarding loaded config. Proceeding to manual entry."
                unset USER_SSID USER_PASS USER_IP USER_GW NEW_USER NEW_PASS
            fi
        fi
    fi
fi

# --- Manual Configuration Input + Review Loop --------------------------------
if [[ "$CONFIG_CONFIRMED" != true ]]; then
    while true; do
        echo ""
        read -p "  WiFi SSID        : " USER_SSID
        read_secret USER_PASS       "  WiFi Password    : "
        read -p "  Desired Static IP: " USER_IP
        read -p "  Gateway IP       : " USER_GW
        read -p "  New Linux User   : " NEW_USER
        read_secret NEW_PASS        "  Password for $NEW_USER: "

        echo ""
        echo "-----------------------------------------------------------------------"
        echo "Review your configuration:"
        echo "  WiFi SSID       : $USER_SSID"
        echo "  WiFi Password   : ********"
        echo "  Static IP       : $USER_IP"
        echo "  Gateway IP      : $USER_GW"
        echo "  Linux Username  : $NEW_USER"
        echo "  Linux Password  : ********"
        echo "-----------------------------------------------------------------------"
        read -p "Is this correct? (Y/n): " CONFIRM

        if [[ ! "$CONFIRM" =~ ^[Nn]$ ]]; then
            break
        fi

        echo ""
        echo "Which fields would you like to change?"
        echo "  1) WiFi SSID"
        echo "  2) WiFi Password"
        echo "  3) Static IP"
        echo "  4) Gateway IP"
        echo "  5) Linux Username"
        echo "  6) Linux Password"
        echo "  7) Re-enter everything"
        echo ""
        read -p "Enter numbers separated by spaces (e.g. 1 3), or 7 to redo all: " FIELDS_TO_CHANGE

        if [[ "$FIELDS_TO_CHANGE" == *"7"* ]]; then
            continue
        fi

        for field in $FIELDS_TO_CHANGE; do
            case "$field" in
                1) read -p "  WiFi SSID        : " USER_SSID ;;
                2) read_secret USER_PASS "  WiFi Password    : " ;;
                3) read -p "  Desired Static IP: " USER_IP ;;
                4) read -p "  Gateway IP       : " USER_GW ;;
                5) read -p "  New Linux User   : " NEW_USER ;;
                6) read_secret NEW_PASS "  Password for $NEW_USER: " ;;
                *) echo "  Unknown field '$field', skipping." ;;
            esac
        done
        # Loop back to review
    done

    # --- Offer to Save Configuration -----------------------------------------
    # Only shown when config was entered manually, never after loading from file
    echo ""
    echo "-----------------------------------------------------------------------"
    read -p "Save this configuration for future installs? (y/N): " SAVE_CHOICE
    if [[ "$SAVE_CHOICE" =~ ^[Yy]$ ]]; then
        while true; do
            read_secret SAVE_PASS1 "  Set a passphrase for the config file: "
            read_secret SAVE_PASS2 "  Confirm passphrase                  : "
            if [[ "$SAVE_PASS1" == "$SAVE_PASS2" ]]; then
                if [[ -z "$SAVE_PASS1" ]]; then
                    echo "  Error: Passphrase cannot be empty."
                    continue
                fi
                CONFIG_DATA="USER_SSID=$USER_SSID
USER_PASS=$USER_PASS
USER_IP=$USER_IP
USER_GW=$USER_GW
NEW_USER=$NEW_USER
NEW_PASS=$NEW_PASS"
                encrypt_config "$CONFIG_DATA" "$SAVE_PASS1"
                log "Configuration saved and encrypted to $SAVED_CONFIG_FILE"
                break
            else
                echo "  Passphrases do not match. Please try again."
            fi
        done
    fi
fi

# --- Summary Before Build ----------------------------------------------------
echo ""
echo "======================================================================="
echo "Build Summary"
echo "======================================================================="
echo "  Distro           : $SELECTED_DISTRO"
echo "  Disk Image Size  : $IMAGE_SIZE_HUMAN (${IMAGE_SIZE_MIB} MiB)"
echo "  WiFi SSID        : $USER_SSID"
echo "  Static IP        : $USER_IP"
echo "  Gateway          : $USER_GW"
echo "  Linux Username   : $NEW_USER"
echo "======================================================================="
read -p "Proceed with build and deployment? (Y/n): " FINAL_CONFIRM
if [[ "$FINAL_CONFIRM" =~ ^[Nn]$ ]]; then
    log "Aborted by user."
    exit 0
fi

# --- Image Generation --------------------------------------------------------
log "Building base $SELECTED_DISTRO image via Podman..."
podman build --arch aarch64 -t "$PODMAN_BASE_TAG" -f "$SELECTED_CONTAINERFILE" .

log "Injecting user configuration into image..."

# Resolve the user-add command now that $NEW_USER is confirmed.
# Expanding it here (on the host) means the Containerfile gets a literal
# username string — no shell variable indirection inside the container RUN layer.
if [[ "$USER_ADD_TOOL" == "adduser_alpine" ]]; then
    RESOLVED_USER_ADD="adduser -D $NEW_USER"
else
    RESOLVED_USER_ADD="useradd -m -s /bin/bash $NEW_USER"
fi

cat <<EOF > .temp_dockerfile
FROM $PODMAN_BASE_TAG
ENV PIVOT_USER=$NEW_USER
COPY overlay/root/alpine-setup.sh /root/alpine-setup.sh
COPY overlay/root/wifi-run.sh /root/wifi-run.sh
RUN chmod +x /root/*.sh && \\
    sed -i 's|SSID|"$USER_SSID"|g' /root/alpine-setup.sh && \\
    sed -i 's|PASS|"$USER_PASS"|g' /root/alpine-setup.sh && \\
    sed -i 's|IP_ADDRESS|$USER_IP|g' /root/alpine-setup.sh && \\
    sed -i 's|GATEWAY_IP|$USER_GW|g' /root/alpine-setup.sh && \\
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
