#!/bin/bash
set -e

S=/home/chirag/usb-staging
rm -rf "$S"
mkdir -p "$S/EFI/BOOT" "$S/dtb"

# Copy GRUB EFI binary
cp /tmp/BOOTAA64.EFI "$S/EFI/BOOT/BOOTAA64.EFI"

# Copy GRUB config
cp /mnt/c/Development/Projects/linux-lenovo-ideacentre-mini-x/scripts/grub.cfg "$S/EFI/BOOT/grub.cfg"

# Copy kernel Image
cp /home/chirag/kernel/misaleh-linux/arch/arm64/boot/Image "$S/Image"

# Copy DTB
cp /home/chirag/kernel/misaleh-linux/arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-x-gen10.dtb "$S/dtb/"

# Copy initramfs
cp /tmp/initramfs.cpio.gz "$S/initramfs.cpio.gz"

echo "Staging directory contents:"
find "$S" -type f -exec ls -lh {} \;
echo ""
echo "Total size:"
du -sh "$S"
