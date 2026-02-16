#!/bin/bash
# Build a minimal initramfs with busybox for first test boot
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
  modprobe insmod lsmod sysctl hostname date; do
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
echo "========================================="
echo ""
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo ""

echo "=== dmesg ==="
dmesg

echo ""
echo "=== /proc/cpuinfo ==="
cat /proc/cpuinfo

echo ""
echo "=== /proc/iomem ==="
cat /proc/iomem

echo ""
echo "=== /proc/interrupts ==="
cat /proc/interrupts

echo ""
echo "=== /sys/firmware/devicetree ==="
ls -la /sys/firmware/devicetree/base/ 2>/dev/null || echo "No device tree found"

echo ""
echo "=== Block devices ==="
cat /proc/partitions

echo ""
echo "=== Network interfaces ==="
ip link 2>/dev/null || echo "ip not available"

echo ""
echo "=== PCI devices ==="
for dev in /sys/bus/pci/devices/*/; do
  vendor=$(cat ${dev}vendor 2>/dev/null)
  device=$(cat ${dev}device 2>/dev/null)
  class=$(cat ${dev}class 2>/dev/null)
  echo "${dev##*/}: vendor=$vendor device=$device class=$class"
done

echo ""
echo "=== Platform devices ==="
ls /sys/bus/platform/devices/ 2>/dev/null | head -50

echo ""
echo "========================================="
echo "  Hardware audit complete."
echo "  Dropping to shell."
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
