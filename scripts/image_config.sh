#!/bin/bash

configure_image_size() {
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
}
