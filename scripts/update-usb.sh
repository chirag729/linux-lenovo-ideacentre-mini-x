#!/bin/bash
# Copy updated initramfs and grub.cfg to Windows staging directory
set -e

SRC_INITRAMFS=/tmp/initramfs.cpio.gz
SRC_GRUB=/mnt/c/Development/Projects/linux-lenovo-ideacentre-mini-x/scripts/grub.cfg
DST=/mnt/c/Development/Projects/linux-lenovo-ideacentre-mini-x/usb-staging

mkdir -p "$DST/EFI/BOOT"
cp "$SRC_INITRAMFS" "$DST/initramfs.cpio.gz"
cp "$SRC_GRUB" "$DST/EFI/BOOT/grub.cfg"

echo "Updated staging:"
ls -lh "$DST/initramfs.cpio.gz" "$DST/EFI/BOOT/grub.cfg"
