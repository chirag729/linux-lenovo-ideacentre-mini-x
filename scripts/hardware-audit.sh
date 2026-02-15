#!/bin/bash
# hardware-audit.sh
# Run this on the Lenovo IdeaCentre when booted into Linux.
# It captures all hardware information and saves to a directory.
#
# Usage: ./hardware-audit.sh [output-dir]
# Default output: /mnt/capture/ (for USB stick) or ./hardware-audit-$(date +%Y%m%d)/

set -euo pipefail

OUTDIR="${1:-./hardware-audit-$(date +%Y%m%d)}"
mkdir -p "$OUTDIR"

echo "=== Linux Hardware Audit for Lenovo IdeaCentre Mini x ==="
echo "Output directory: $OUTDIR"
echo "Date: $(date -u)"
echo ""

capture() {
    local name="$1"
    shift
    echo "Capturing: $name ..."
    "$@" > "$OUTDIR/$name" 2>&1 || echo "[FAILED] $name (exit $?)"
}

# Kernel and boot info
capture "uname.txt"         uname -a
capture "cmdline.txt"       cat /proc/cmdline
capture "dmesg.txt"         dmesg
capture "dmesg-notime.txt"  dmesg -T

# CPU and memory
capture "cpuinfo.txt"       cat /proc/cpuinfo
capture "meminfo.txt"       cat /proc/meminfo
capture "iomem.txt"         cat /proc/iomem
capture "ioports.txt"       cat /proc/ioports
capture "interrupts.txt"    cat /proc/interrupts

# PCI devices (critical for identifying Ethernet, WiFi, GPU, NVMe)
capture "lspci.txt"         lspci -vvnn
capture "lspci-tree.txt"    lspci -tv

# USB devices and topology
capture "lsusb-tree.txt"    lsusb -t
capture "lsusb-verbose.txt" lsusb -v

# Block devices and storage
capture "lsblk.txt"         lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL,TRAN
capture "nvme-list.txt"     nvme list 2>/dev/null || echo "nvme-cli not installed"

# Network
capture "ip-link.txt"       ip link show
capture "ip-addr.txt"       ip addr show

# Device tree (live)
if [ -d /proc/device-tree ]; then
    capture "dt-model.txt"      cat /proc/device-tree/model
    capture "dt-compatible.txt" cat /proc/device-tree/compatible
    # Dump full DT node list
    find /proc/device-tree/ -type f 2>/dev/null | sort > "$OUTDIR/dt-nodes.txt"
    # Dump the full compiled DT if dtc is available
    if command -v dtc &>/dev/null; then
        dtc -I fs /proc/device-tree -O dts > "$OUTDIR/dt-decompiled.dts" 2>/dev/null || true
    fi
fi

# ACPI tables (may exist even with DT boot)
if [ -d /sys/firmware/acpi/tables ]; then
    mkdir -p "$OUTDIR/acpi-tables"
    cp -r /sys/firmware/acpi/tables/* "$OUTDIR/acpi-tables/" 2>/dev/null || true
    echo "ACPI tables captured" > "$OUTDIR/acpi-tables/README.txt"
fi

# DMI/SMBIOS
capture "dmidecode.txt"     dmidecode 2>/dev/null || echo "dmidecode not available"

# Regulators
capture "regulators.txt"    bash -c 'for r in /sys/class/regulator/regulator.*/; do
    echo "=== $(basename $r) ==="
    cat "$r/name" 2>/dev/null
    echo "  state: $(cat "$r/state" 2>/dev/null)"
    echo "  microvolts: $(cat "$r/microvolts" 2>/dev/null)"
    echo ""
done'

# Thermal zones
capture "thermal.txt"       bash -c 'for t in /sys/class/thermal/thermal_zone*/; do
    echo "=== $(basename $t) ==="
    echo "  type: $(cat "$t/type" 2>/dev/null)"
    echo "  temp: $(cat "$t/temp" 2>/dev/null)"
    echo ""
done'

# I2C buses and devices
capture "i2c-buses.txt"     bash -c 'ls -la /sys/bus/i2c/devices/ 2>/dev/null || echo "no i2c devices"'

# GPIO controllers
capture "gpio-controllers.txt" bash -c 'ls -la /sys/class/gpio/ 2>/dev/null || echo "no gpio sysfs"'

# Sound devices
capture "sound-cards.txt"   bash -c 'cat /proc/asound/cards 2>/dev/null || echo "no ALSA cards"'
capture "sound-devices.txt" bash -c 'cat /proc/asound/devices 2>/dev/null || echo "no ALSA devices"'

# DRM/display
capture "drm-info.txt"      bash -c 'for c in /sys/class/drm/card*; do
    echo "=== $(basename $c) ==="
    cat "$c/device/uevent" 2>/dev/null
    echo "  status: $(cat "$c/status" 2>/dev/null)"
    echo "  enabled: $(cat "$c/enabled" 2>/dev/null)"
    echo ""
done'

# Firmware
capture "firmware-loading.txt" dmesg | grep -i firmware || true

# Module list
capture "modules.txt"       lsmod 2>/dev/null || echo "no modules loaded (built-in kernel)"

# Kernel config if available
capture "kernel-config.txt" bash -c 'zcat /proc/config.gz 2>/dev/null || echo "config not available"'

echo ""
echo "=== Audit complete ==="
echo "Files saved to: $OUTDIR"
echo "Total files: $(find "$OUTDIR" -type f | wc -l)"
ls -la "$OUTDIR"
