#!/bin/bash
# build-kernel.sh
# Build the Linux kernel on the Raspberry Pi 5 for the Lenovo IdeaCentre Mini x.
#
# Usage: ./build-kernel.sh [--full|--dtbs-only|--image-only]
#
# Prerequisites:
#   sudo apt install build-essential flex bison libssl-dev libelf-dev bc device-tree-compiler

set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:-$HOME/kernel/linux}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="${1:---full}"
JOBS="${JOBS:-3}"

echo "=== Kernel Build for Lenovo IdeaCentre Mini x ==="
echo "Kernel source: $KERNEL_DIR"
echo "Project dir:   $PROJECT_DIR"
echo "Build mode:    $BUILD_MODE"
echo "Parallel jobs: $JOBS"
echo "Architecture:  $(uname -m)"
echo ""

if [ ! -d "$KERNEL_DIR" ]; then
    echo "ERROR: Kernel source not found at $KERNEL_DIR"
    echo "Clone it with: git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git $KERNEL_DIR"
    exit 1
fi

cd "$KERNEL_DIR"

# Copy our defconfig if it exists
if [ -f "$PROJECT_DIR/kernel/defconfig" ]; then
    echo "Using project defconfig..."
    cp "$PROJECT_DIR/kernel/defconfig" arch/arm64/configs/ideacentre_defconfig
    make ideacentre_defconfig
else
    echo "No project defconfig found, using Mostafa's qcom_defconfig if available..."
    if [ -f arch/arm64/configs/qcom_defconfig ]; then
        make qcom_defconfig
    else
        echo "ERROR: No suitable defconfig found. Create kernel/defconfig in the project."
        exit 1
    fi
fi

# Copy our DTS if it exists
if [ -f "$PROJECT_DIR/dts/x1p42100-lenovo-ideacentre-mini-x.dts" ]; then
    echo "Copying project DTS to kernel tree..."
    cp "$PROJECT_DIR/dts/x1p42100-lenovo-ideacentre-mini-x.dts" \
       arch/arm64/boot/dts/qcom/
fi

START_TIME=$(date +%s)

case "$BUILD_MODE" in
    --full)
        echo "Building kernel image + DTBs + modules..."
        make -j"$JOBS" Image dtbs modules
        ;;
    --dtbs-only)
        echo "Building device tree binaries only..."
        make -j"$JOBS" dtbs
        ;;
    --image-only)
        echo "Building kernel image only..."
        make -j"$JOBS" Image
        ;;
    *)
        echo "Unknown build mode: $BUILD_MODE"
        echo "Usage: $0 [--full|--dtbs-only|--image-only]"
        exit 1
        ;;
esac

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
echo ""
echo "Build completed in ${ELAPSED}s ($(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s)"

# Report output locations
echo ""
echo "Output files:"
if [ -f arch/arm64/boot/Image ]; then
    ls -lh arch/arm64/boot/Image
fi
# Find our DTB
DTB="arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-mini-x.dtb"
if [ -f "$DTB" ]; then
    ls -lh "$DTB"
else
    echo "Note: IdeaCentre DTB not found. Check if the DTS file is in place."
    echo "Available x1p DTBs:"
    ls arch/arm64/boot/dts/qcom/x1p*.dtb 2>/dev/null || echo "  (none)"
fi
