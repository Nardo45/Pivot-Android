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

1.  **Root Privileges:** **Mandatory.** Your device must be rooted (e.g., via Magisk) to allow for namespace manipulation, loop device mounting, and hardware node access.
2.  **BusyBox (Android NDK):** You must install the **Busybox for Android NDK** Magisk module by **osm0sis @ xda-developers**. This provides the necessary command-line utilities for the pivot process.
    * **Recommended Method:** Use the **MMRL** (Magisk Module Repo Loader) app on your rooted device.
    * **Setup:** Add the **"Googlers Magisk Repo"** within MMRL, then search for and install the Busybox for Android NDK zip.
    * *Note:* While the zip can be found elsewhere, MMRL is the verified method for this workflow.
3.  **Termux:** The recommended terminal environment for triggering the initialization during the beta phase.
4.  **Namespace Utilities:** `nsenter` is required to transition to the global mount namespace.

---

## Project Structure

To maintain modularity and prepare for specific device support, the project is organized as follows:

```text
Pivot-Android/
├── core/                    # Universal pivot logic and binaries
│   ├── pvroot.sh            # Main execution engine
│   ├── set_rprivate.c       # Source for mount propagation fixes
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

## Installation and Deployment

### 1. Building the Rootfs (Host Side)
Before deploying to the device, you must generate an `aarch64` Alpine Linux rootfs. This process uses Podman and QEMU emulation on an x86_64 host to ensure a clean, architecture-correct environment.

**Build and Export:**
```bash
# Build the image using the provided Containerfile
podman build --platform linux/arm64 -t pivot-build-temp .

# Create a temporary container instance and export the rootfs
CONTAINER_ID=$(podman create pivot-build-temp)
podman export $CONTAINER_ID | gzip > alpine-rootfs-aarch64.tar.gz

# Cleanup
podman rm $CONTAINER_ID
```

### 2. Automated Deployment via `install.sh`
The project includes an `install.sh` script to automate the transfer of binaries and scripts to the device via ADB. 

**Note on Permissions:** This script executes `adb root` to push files directly into the Termux private data directory. **A rooted Android device is required** because standard user permissions do not allow for the high-level mount and namespace operations performed by this framework.

```bash
# Run from the project root on your host machine
chmod +x install.sh
./install.sh
```

### 3. Initializing the Rootfs Image (Device Side)
The `restore_archive.sh` tool handles image creation and extraction. It utilizes **sparse files** via `truncate`, allowing you to allocate a large virtual disk (e.g., 20 GiB) without immediately consuming physical storage.

**Example (Creating a 20 GiB image):**
```bash
# Run via ADB or within Termux
cd /data/data/com.termux/files/home
./restore_archive.sh alpine-rootfs-aarch64.tar.gz 20480
```
*Tip: To calculate MiB for a specific size in GiB, multiply your desired GiB by 1024.*

---

## Execution: Performing the Userspace Pivot

To successfully execute a userspace takeover, `pvroot.sh` must be run within the global mount namespace. Execute the following command:

**From Termux (Non-root shell):**
```bash
su -c "nsenter --mount=/proc/1/ns/mnt sh /data/data/com.termux/files/home/pvroot.sh"
```

**From ADB Shell:**
```bash
cd /data/data/com.termux/files/home
sh pvroot.sh
```

Upon success, the Android userspace will be moved to `/android_root` and you will be dropped into a standard Linux shell. Wi-Fi and SSH services will be initialized automatically if the image is configured correctly.

---

## Debugging and ADB Persistence

By default, the framework attempts to transition fully into the Linux userspace, which involves backgrounding setup tasks that will terminate existing Android-side processes (including `adbd`). 

### Using the `--adb` Flag
If you are troubleshooting a new device or testing network bring-up, you can run the pivot script with the `--adb` flag:

```bash
sh pvroot.sh --adb
```

**Why use this?**
* **Process Retention:** This prevents the execution of `alpine-setup.sh`. By doing so, the current ADB daemon (`adbd`) remains resident in memory despite the filesystem swap.
* **Persistent Connection:** You will maintain your active shell into the Alpine environment through your existing ADB session even after the pivot.

**Critical Limitations:**
* **Session Fragility:** The ADB connection is held by processes currently in RAM. If you terminate the session or disconnect the cable, the ADB daemon will likely fail to restart in the new userspace. You will be forced to reboot the hardware to regain access.
* **Manual Setup:** Since `alpine-setup.sh` is skipped, you must manually configure networking or services from within the Alpine shell.

---

## Script Reference

* `pvroot.sh`: The core engine that resolves mount propagation, binds hardware nodes, and executes `pivot_root`.
* `restore_archive.sh`: Handles the creation, formatting, and extraction of the rootfs image.
* `install.sh`: Host-side script for deploying the framework to a rooted Android device via ADB.
* `set_rprivate`: A compiled utility used to set the root filesystem mount propagation to private, which is a kernel requirement for the `pivot_root` syscall.

---

## Future Roadmap: The Kernel A/B Framework

The objective of this project is to evolve from userspace takeovers into a sophisticated **Dual-Kernel Hot-Swap** system utilizing `kexec`.

### Concept of Operations
1.  **Kernel A (Android):** The primary stock kernel ensures the device remains a fully functional smartphone upon boot.
2.  **The Transition:** The pivot script prepares the environment for a `kexec` jump.
3.  **Kernel B (Mainline/Target):** The system loads a secondary kernel, either a mainline Linux kernel or a modified downstream kernel, and transitions execution without a hardware reboot.

### Implications for Development
This framework aims to bridge the gap between experimental mobile Linux development (such as postmarketOS) and daily-driver stability. By providing a "safe" path to test mainline kernels, developers can debug hardware support while maintaining the ability to revert to a stable Android environment with a simple reboot. This positions the Android device as a versatile platform capable of serving as a mobile workstation for academic, professional, and entertainment purposes.
