#!/bin/bash
set -e

SRC=/home/chirag/usb-staging
DST=/mnt/e

echo "Copying boot files to USB (E:)..."

# Create directory structure
mkdir -p "$DST/EFI/BOOT"
mkdir -p "$DST/dtb"

# Copy GRUB EFI bootloader
cp "$SRC/EFI/BOOT/BOOTAA64.EFI" "$DST/EFI/BOOT/BOOTAA64.EFI"
echo "  BOOTAA64.EFI copied"

# Copy GRUB config
cp "$SRC/EFI/BOOT/grub.cfg" "$DST/EFI/BOOT/grub.cfg"
echo "  grub.cfg copied"

# Copy kernel
cp "$SRC/Image" "$DST/Image"
echo "  Image copied (kernel)"

# Copy device tree
cp "$SRC/dtb/x1p42100-lenovo-ideacentre-x-gen10.dtb" "$DST/dtb/"
echo "  DTB copied"

# Copy initramfs
cp "$SRC/initramfs.cpio.gz" "$DST/initramfs.cpio.gz"
echo "  initramfs.cpio.gz copied"

echo ""
echo "USB contents:"
find "$DST" -type f -exec ls -lh {} \;
echo ""
echo "USB space used:"
du -sh "$DST"
