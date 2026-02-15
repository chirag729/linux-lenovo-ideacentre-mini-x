#!/bin/bash
# make-bootable-usb.sh
# Create a bootable USB drive from a built kernel for the Lenovo IdeaCentre Mini x.
#
# This creates a minimal EFI-bootable USB with:
# - Kernel Image
# - Device Tree Binary (.dtb)
# - Minimal initramfs (if provided)
# - EFI boot entry
#
# Usage: ./make-bootable-usb.sh <usb-device> [--with-rootfs <rootfs.tar.gz>]
#
# Example: ./make-bootable-usb.sh /dev/sda
#
# WARNING: This will ERASE the target device. Double-check the device path.

set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:-$HOME/kernel/linux}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USB_DEV="${1:-}"
ROOTFS_ARG="${2:-}"
ROOTFS_TAR="${3:-}"

if [ -z "$USB_DEV" ]; then
    echo "Usage: $0 <usb-device> [--with-rootfs <rootfs.tar.gz>]"
    echo ""
    echo "Available block devices:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part"
    echo ""
    echo "WARNING: Choose carefully. This will erase the target device."
    exit 1
fi

if [ ! -b "$USB_DEV" ]; then
    echo "ERROR: $USB_DEV is not a block device"
    exit 1
fi

# Safety check -- refuse to write to the boot disk
BOOT_DISK=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
if [ "$USB_DEV" = "$BOOT_DISK" ]; then
    echo "ERROR: $USB_DEV appears to be the boot disk. Refusing to continue."
    exit 1
fi

KERNEL_IMAGE="$KERNEL_DIR/arch/arm64/boot/Image"
DTB_FILE="$KERNEL_DIR/arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-mini-x.dtb"

if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "ERROR: Kernel image not found at $KERNEL_IMAGE"
    echo "Build it first with: ./build-kernel.sh"
    exit 1
fi

echo "=== Create Bootable USB for Lenovo IdeaCentre Mini x ==="
echo "Target device: $USB_DEV"
echo "Kernel image:  $KERNEL_IMAGE ($(stat -c %s "$KERNEL_IMAGE" | numfmt --to=iec))"
if [ -f "$DTB_FILE" ]; then
    echo "DTB file:      $DTB_FILE"
else
    echo "DTB file:      NOT FOUND (will try CRD DTB as fallback)"
    DTB_FILE="$KERNEL_DIR/arch/arm64/boot/dts/qcom/x1p42100-crd.dtb"
    if [ -f "$DTB_FILE" ]; then
        echo "Fallback DTB:  $DTB_FILE"
    else
        echo "ERROR: No suitable DTB found."
        exit 1
    fi
fi
echo ""
echo "WARNING: This will ERASE ALL DATA on $USB_DEV"
read -p "Type 'yes' to continue: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Partitioning $USB_DEV..."

# Create GPT with:
# Partition 1: 512MB EFI System Partition (FAT32)
# Partition 2: Remaining space for rootfs (ext4)
# Partition 3: 256MB capture partition (FAT32, for hardware audit output)

# Using sfdisk for scriptable partitioning
sfdisk "$USB_DEV" <<EOF
label: gpt
size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
size=+, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="rootfs"
EOF

# Wait for partition devices
sleep 2
partprobe "$USB_DEV" 2>/dev/null || true
sleep 1

# Determine partition device names (handle both /dev/sdX1 and /dev/nvmeXn1p1 styles)
if [[ "$USB_DEV" =~ [0-9]$ ]]; then
    EFI_PART="${USB_DEV}p1"
    ROOT_PART="${USB_DEV}p2"
else
    EFI_PART="${USB_DEV}1"
    ROOT_PART="${USB_DEV}2"
fi

echo "Formatting partitions..."
mkfs.vfat -F32 -n "EFI" "$EFI_PART"
mkfs.ext4 -L "rootfs" "$ROOT_PART"

# Mount and populate EFI partition
MOUNT_EFI=$(mktemp -d)
mount "$EFI_PART" "$MOUNT_EFI"

mkdir -p "$MOUNT_EFI/EFI/BOOT"
mkdir -p "$MOUNT_EFI/dtbs"
mkdir -p "$MOUNT_EFI/capture"

# Copy kernel
cp "$KERNEL_IMAGE" "$MOUNT_EFI/EFI/BOOT/Image"

# Copy DTB
cp "$DTB_FILE" "$MOUNT_EFI/dtbs/"

# Copy hardware audit script
cp "$PROJECT_DIR/scripts/hardware-audit.sh" "$MOUNT_EFI/capture/"

echo "EFI partition populated:"
find "$MOUNT_EFI" -type f -exec ls -lh {} \;

umount "$MOUNT_EFI"
rmdir "$MOUNT_EFI"

# If rootfs tarball provided, extract it
if [ "$ROOTFS_ARG" = "--with-rootfs" ] && [ -n "$ROOTFS_TAR" ] && [ -f "$ROOTFS_TAR" ]; then
    MOUNT_ROOT=$(mktemp -d)
    mount "$ROOT_PART" "$MOUNT_ROOT"
    echo "Extracting rootfs..."
    tar xf "$ROOTFS_TAR" -C "$MOUNT_ROOT"
    umount "$MOUNT_ROOT"
    rmdir "$MOUNT_ROOT"
fi

echo ""
echo "=== USB drive ready ==="
echo "EFI partition: $EFI_PART"
echo "Root partition: $ROOT_PART"
echo ""
echo "Note: You still need a bootloader (systemd-boot or GRUB) configured"
echo "to chainload the kernel with the correct DTB and root= parameter."
echo "For initial testing, you can use the UEFI shell to boot manually."
