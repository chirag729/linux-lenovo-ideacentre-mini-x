#!/bin/bash
set -e

SRC=/home/chirag/usb-staging
DST=/mnt/c/Development/Projects/linux-lenovo-ideacentre-mini-x/usb-staging

rm -rf "$DST"
mkdir -p "$DST/EFI/BOOT" "$DST/dtb"

cp "$SRC/EFI/BOOT/BOOTAA64.EFI" "$DST/EFI/BOOT/"
cp "$SRC/EFI/BOOT/grub.cfg"     "$DST/EFI/BOOT/"
cp "$SRC/Image"                  "$DST/"
cp "$SRC/dtb/x1p42100-lenovo-ideacentre-x-gen10.dtb" "$DST/dtb/"
cp "$SRC/initramfs.cpio.gz"      "$DST/"

echo "Copied to Windows filesystem:"
find "$DST" -type f -exec ls -lh {} \;
