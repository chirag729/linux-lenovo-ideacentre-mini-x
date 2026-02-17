#!/bin/bash
# Build a minimal initramfs with busybox for first test boot
# The init script writes all hardware data to the USB stick's FAT32 partition,
# so we can read it from Windows without needing display output.
set -e

OUTDIR=/tmp/initramfs-build
OUTFILE=/tmp/initramfs.cpio.gz

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"/{bin,sbin,etc,proc,sys,dev,tmp,run,mnt,usr/bin,usr/sbin}

# Copy busybox static binary
cp /usr/bin/busybox "$OUTDIR/bin/busybox"

# Create symlinks for key busybox applets
for cmd in sh ash init mount umount mkdir ls cat echo dmesg ip ifconfig udhcpc sleep \
  reboot poweroff ln mknod grep sed awk vi cp mv rm find less head tail \
  modprobe insmod lsmod sysctl hostname date sync; do
  ln -sf busybox "$OUTDIR/bin/$cmd"
done

# Create init script
cat > "$OUTDIR/init" << 'INITEOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts

echo "========================================="
echo "  Lenovo IdeaCentre Mini x - Test Boot"
echo "  Blind boot: writing logs to USB stick"
echo "========================================="

# Wait a few seconds for block devices to appear
echo "Waiting for block devices..."
sleep 5

# Find and mount the USB FAT32 partition (the one we booted from)
# Look for vfat partitions - try common device names
LOGDIR=""
for dev in /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sda /dev/sdb /dev/sdc \
           /dev/nvme0n1p1 /dev/mmcblk0p1; do
  if [ -b "$dev" ]; then
    echo "Trying to mount $dev..."
    mkdir -p /mnt/usb
    if mount -t vfat "$dev" /mnt/usb 2>/dev/null; then
      # Check if this is our boot USB (has our Image file)
      if [ -f /mnt/usb/Image ] || [ -f /mnt/usb/EFI/BOOT/BOOTAA64.EFI ]; then
        LOGDIR="/mnt/usb/logs"
        mkdir -p "$LOGDIR"
        echo "Found boot USB at $dev, logging to $LOGDIR"
        break
      fi
      umount /mnt/usb
    fi
  fi
done

if [ -z "$LOGDIR" ]; then
  echo "WARNING: Could not find USB stick to write logs."
  echo "Dumping to console only."
  LOGDIR="/tmp"
fi

# Capture timestamp
date > "$LOGDIR/boot-timestamp.txt" 2>/dev/null || true

# Capture dmesg
echo "Capturing dmesg..."
dmesg > "$LOGDIR/dmesg.txt" 2>&1

# Capture cpuinfo
echo "Capturing cpuinfo..."
cat /proc/cpuinfo > "$LOGDIR/cpuinfo.txt" 2>&1

# Capture iomem
echo "Capturing iomem..."
cat /proc/iomem > "$LOGDIR/iomem.txt" 2>&1

# Capture interrupts
echo "Capturing interrupts..."
cat /proc/interrupts > "$LOGDIR/interrupts.txt" 2>&1

# Capture device tree
echo "Capturing device tree info..."
if [ -d /sys/firmware/devicetree/base ]; then
  ls -laR /sys/firmware/devicetree/base/ > "$LOGDIR/devicetree-listing.txt" 2>&1
  # Capture the compatible string for the root node
  cat /sys/firmware/devicetree/base/compatible > "$LOGDIR/dt-compatible.txt" 2>/dev/null || true
  echo "Device tree found" >> "$LOGDIR/devicetree-listing.txt"
else
  echo "No device tree found" > "$LOGDIR/devicetree-listing.txt"
fi

# Capture block devices
echo "Capturing block devices..."
cat /proc/partitions > "$LOGDIR/partitions.txt" 2>&1

# Capture network interfaces
echo "Capturing network interfaces..."
ip link > "$LOGDIR/ip-link.txt" 2>&1
ip addr > "$LOGDIR/ip-addr.txt" 2>&1

# Capture PCI devices
echo "Capturing PCI devices..."
{
  for pcidev in /sys/bus/pci/devices/*/; do
    vendor=$(cat "${pcidev}vendor" 2>/dev/null)
    device=$(cat "${pcidev}device" 2>/dev/null)
    class=$(cat "${pcidev}class" 2>/dev/null)
    driver=$(readlink "${pcidev}driver" 2>/dev/null)
    driver=${driver##*/}
    echo "${pcidev##*/}: vendor=$vendor device=$device class=$class driver=$driver"
  done
} > "$LOGDIR/pci-devices.txt" 2>&1

# Capture USB devices
echo "Capturing USB devices..."
{
  for usbdev in /sys/bus/usb/devices/*/; do
    if [ -f "${usbdev}idVendor" ]; then
      vid=$(cat "${usbdev}idVendor" 2>/dev/null)
      pid=$(cat "${usbdev}idProduct" 2>/dev/null)
      prod=$(cat "${usbdev}product" 2>/dev/null)
      mfg=$(cat "${usbdev}manufacturer" 2>/dev/null)
      echo "${usbdev##*/}: vid=$vid pid=$pid product='$prod' manufacturer='$mfg'"
    fi
  done
} > "$LOGDIR/usb-devices.txt" 2>&1

# Capture platform devices
echo "Capturing platform devices..."
ls /sys/bus/platform/devices/ > "$LOGDIR/platform-devices.txt" 2>&1

# Capture loaded modules (if any)
echo "Capturing modules..."
cat /proc/modules > "$LOGDIR/modules.txt" 2>&1 || true

# Capture cmdline
echo "Capturing cmdline..."
cat /proc/cmdline > "$LOGDIR/cmdline.txt" 2>&1

# Capture ACPI info if available
echo "Capturing ACPI info..."
ls /sys/firmware/acpi/tables/ > "$LOGDIR/acpi-tables-list.txt" 2>&1 || echo "No ACPI" > "$LOGDIR/acpi-tables-list.txt"

# Capture clock info
echo "Capturing clock info..."
{
  if [ -d /sys/kernel/debug ]; then
    mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
    cat /sys/kernel/debug/clk/clk_summary 2>/dev/null || echo "clk_summary not available"
  fi
} > "$LOGDIR/clk-summary.txt" 2>&1

# Capture regulator info
{
  for reg in /sys/class/regulator/*/; do
    name=$(cat "${reg}name" 2>/dev/null)
    state=$(cat "${reg}state" 2>/dev/null)
    echo "${reg##*/}: name=$name state=$state"
  done
} > "$LOGDIR/regulators.txt" 2>&1

# Write summary
echo "Writing summary..."
{
  echo "========================================="
  echo "  Lenovo IdeaCentre Mini x - Boot Log"
  echo "========================================="
  echo ""
  echo "Kernel: $(uname -r)"
  echo "Architecture: $(uname -m)"
  echo "Cmdline: $(cat /proc/cmdline)"
  echo "Date: $(date 2>/dev/null || echo 'unknown')"
  echo "Log directory: $LOGDIR"
  echo ""
  echo "Files captured:"
  ls -la "$LOGDIR/"
} > "$LOGDIR/summary.txt" 2>&1

# Sync to make sure everything is written
echo "Syncing..."
sync
sleep 2
sync

echo ""
echo "========================================="
echo "  Logs written to USB stick."
echo "  Files in $LOGDIR/"
echo "  Dropping to shell (or reboot)."
echo "========================================="
echo ""

# Try to bring up Ethernet
for iface in eth0 enp5s0 end0; do
  ip link set "$iface" up 2>/dev/null && udhcpc -i "$iface" 2>/dev/null &
done

exec /bin/sh
INITEOF
chmod +x "$OUTDIR/init"

# Build cpio archive
cd "$OUTDIR"
find . | cpio -o -H newc 2>/dev/null | gzip > "$OUTFILE"
echo "Initramfs built: $(ls -lh "$OUTFILE")"
