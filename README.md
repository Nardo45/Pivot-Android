# Pivot-Android

A device-agnostic framework for performing a full userspace takeover on Android devices.

Unlike a chroot or proot, **Pivot-Android** utilizes `pivot_root` to swap the Android userspace for a standard Linux distribution (defaulting to Alpine Linux). This architecture facilitates native performance, proper OpenRC or Systemd service management, and direct hardware interaction

---

## Technical Features

* **Universal Compatibility:** Architected to be device-agnostic, requiring only root access and loop device support.
* **Persistent Connectivity:** Automated configuration scripts ensure Wi-Fi and SSH services are initialized immediately upon pivot.
* **Direct Hardware Interfacing:** Strategic bind-mounting of kernel and hardware nodes (`/sys`, `/proc`, `/dev`) allows the Linux userspace to interact with the underlying SoC.
* **Non-Destructive Execution:** The environment exists entirely in memory and on its dedicated image; a system reboot restores the standard Android environment.

---

## Prerequisites

1.  **Root Privileges:** Necessary for namespace manipulation and mount operations.
2.  **Termux:** The recommended terminal environment for triggering the initialization.
3.  **Namespace Utilities:** `nsenter` is required to transition to the global mount namespace.

---

## Project Structure

To maintain modularity and prepare for specific device support, the project is organized as follows:

```text
Pivot-Android/
├── core/                   # Universal pivot logic and binaries
│   ├── pvroot.sh           # Main execution engine
│   ├── set_rprivate.c      # Source for mount propagation fixes
|   └bin/
│     └── set_rprivate      # Compiled binary for mount management
├── tools/                  # Image and rootfs management utilities
│   ├── create_archive.sh   
│   └── restore_archive.sh  # Installation and restoration script
├── devices/                # Device-specific configurations
│   └── generic/            # Default hardware parameters
├── LICENSE
└── README.md               
```

---

## Installation and Setup

Manual setup of the rootfs image is discouraged. Instead, use the provided `restore_archive.sh` tool to handle image creation, formatting, and extraction.

### Initializing the Rootfs Image

The installation script utilizes `truncate` to create **sparse files**. This allows you to allocate a large virtual disk size (e.g., 50 GiB) without immediately consuming that space on your device's physical storage. The image file will only occupy the actual disk space used by the data contained within it.

**Usage:**
```bash
./restore_archive.sh [OPTIONS] <TARBALL> [SIZE_MB]
```

**Options:**
* `-i IMAGE`: Path to the image file (Default: `/data/local/pivot/alpine_aarch64.img`).
* `-m MOUNTPOINT`: Mount point for the image (Default: `/data/local/pivot/alpine`).
* `-s SIZE_MB`: Desired virtual size in MiB.

**Example (Creating a 50 GiB virtual image):**
```bash
# 51200 MiB = 50 GiB
./restore_archive.sh -s 51200 /sdcard/alpine-rootfs.tar.gz
```

---

## Execution: Performing the Userspace Pivot

To successfully execute a userspace takeover, `pvroot.sh` must be run within the global mount namespace. Failure to do so will result in the application that ran the command to enter a weird state where it's sandbox has pivotted to the image.

Execute the following command from within Termux:

```bash
su -c "nsenter --mount=/proc/1/ns/mnt sh /data/data/com.termux/files/home/pvroot.sh"
```

Upon success, the Android userspace will be moved to `/android_root` and you will be dropped into a standard Linux shell. Wi-Fi and SSH services will be initialized automatically if the image is configured correctly.

---

## Script Reference

* `pvroot.sh`: The core engine that resolves mount propagation, binds essential hardware nodes, and executes `pivot_root`.
* `mount_alpine.sh` / `umount_alpine.sh`: Standard utilities for mounting the image file for offline maintenance.
* `create_rootfs_archive.sh`: Generates a portable `.tar.gz` backup of the existing Alpine environment.
* `set_rprivate.c`: A C utility designed to set the mount propagation of the root filesystem to private, a mandatory step for the `pivot_root` syscall.

---

## Future Roadmap: The Kernel A/B Framework

The objective of this project is to evolve from userspace takeovers into a sophisticated **Dual-Kernel Hot-Swap** system utilizing `kexec`.

### Concept of Operations
1.  **Kernel A (Android):** The primary stock kernel ensures the device remains a fully functional smartphone upon boot.
2.  **The Transition:** The pivot script prepares the environment for a `kexec` jump.
3.  **Kernel B (Mainline/Target):** The system loads a secondary kernel, either a mainline Linux kernel or a modified downstream kernel, and transitions execution without a hardware reboot.

### Implications for Development
This framework aims to bridge the gap between experimental mobile Linux development (such as **postmarketOS**) and daily-driver stability. By providing a "safe" path to test mainline kernels, developers can debug hardware support on experimental kernels while maintaining the ability to revert to a stable Android environment with a simple reboot. This positions the Android device as a versatile platform capable of serving as a mobile workstation for academic, professional, and entertainment purposes.
