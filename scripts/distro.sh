#!/bin/bash

select_distro() {
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
}
