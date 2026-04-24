#!/bin/bash

load_or_collect_user_config() {
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
}

show_build_summary() {
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
}
