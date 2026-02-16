#!/bin/bash
# run-qemu.sh - Boot ARM64 kernel + initramfs in QEMU
# Uses the generic 'virt' machine (NOT the Snapdragon X DTB)
set -e

KERNEL="/home/chirag/kernel/misaleh-linux/arch/arm64/boot/Image"
INITRAMFS="/tmp/initramfs.cpio.gz"

if [ ! -f "$KERNEL" ]; then
    echo "ERROR: Kernel Image not found at $KERNEL"
    exit 1
fi

if [ ! -f "$INITRAMFS" ]; then
    echo "ERROR: Initramfs not found at $INITRAMFS"
    exit 1
fi

echo "=== Booting ARM64 kernel in QEMU ==="
echo "Press Ctrl-A then X to exit QEMU"
echo "==========================================="
echo ""

qemu-system-aarch64 \
    -machine virt \
    -cpu cortex-a76 \
    -m 2048 \
    -nographic \
    -kernel "$KERNEL" \
    -initrd "$INITRAMFS" \
    -append "console=ttyAMA0 earlycon loglevel=8 nomodeset"
