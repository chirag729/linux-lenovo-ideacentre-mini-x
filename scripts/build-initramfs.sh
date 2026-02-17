#!/bin/bash
# Build a minimal initramfs with busybox + dropbear SSH for test booting
# The init script:
#   1. Captures hardware data to the USB stick (blind boot)
#   2. Brings up Ethernet and starts SSH server
#   3. Drops to local shell
#
# Prerequisites (install in WSL2):
#   sudo apt install busybox-static dropbear-bin cpio
#
# Root password for SSH login: "linux"
set -e

OUTDIR=/tmp/initramfs-build
OUTFILE=/tmp/initramfs.cpio.gz

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"/{bin,sbin,etc,proc,sys,dev,tmp,run,mnt,root/.ssh,var/run,lib,usr/bin,usr/sbin}
mkdir -p "$OUTDIR/etc/dropbear"

# --- Busybox ---
cp /usr/bin/busybox "$OUTDIR/bin/busybox"

# Create symlinks for key busybox applets
for cmd in sh ash init mount umount mkdir ls cat echo dmesg ip ifconfig udhcpc sleep \
  reboot poweroff ln mknod grep sed awk vi cp mv rm find less head tail \
  modprobe insmod lsmod sysctl hostname date sync passwd telnetd \
  wget nc tee chmod chown id whoami; do
  ln -sf busybox "$OUTDIR/bin/$cmd"
done

# --- Dropbear SSH ---
DROPBEAR=$(which dropbear 2>/dev/null || true)
DROPBEARKEY=$(which dropbearkey 2>/dev/null || true)

if [ -z "$DROPBEAR" ] || [ -z "$DROPBEARKEY" ]; then
  echo "ERROR: dropbear-bin not installed. Run: sudo apt install dropbear-bin"
  exit 1
fi

cp "$DROPBEAR" "$OUTDIR/usr/sbin/dropbear"
cp "$DROPBEARKEY" "$OUTDIR/usr/bin/dropbearkey"

# Copy shared libraries needed by dropbear
echo "Copying shared libraries for dropbear..."
for bin in "$DROPBEAR" "$DROPBEARKEY"; do
  ldd "$bin" 2>/dev/null | grep -o '/[^ ]*' | while read -r lib; do
    if [ -f "$lib" ]; then
      # Preserve directory structure under /lib
      libdir="$OUTDIR/lib"
      mkdir -p "$libdir"
      cp -n "$lib" "$libdir/" 2>/dev/null || true
    fi
  done
done

# Also copy the dynamic linker
LINKER=$(ldd "$DROPBEAR" 2>/dev/null | grep 'ld-linux' | grep -o '/[^ ]*')
if [ -n "$LINKER" ]; then
  cp -n "$LINKER" "$OUTDIR/lib/" 2>/dev/null || true
  # Create symlink at expected path
  LINKER_NAME=$(basename "$LINKER")
  ln -sf "/lib/$LINKER_NAME" "$OUTDIR/lib/ld-linux-aarch64.so.1" 2>/dev/null || true
fi

# Generate dropbear host keys
echo "Generating SSH host keys..."
"$DROPBEARKEY" -t rsa -f "$OUTDIR/etc/dropbear/dropbear_rsa_host_key" 2>/dev/null
"$DROPBEARKEY" -t ecdsa -f "$OUTDIR/etc/dropbear/dropbear_ecdsa_host_key" 2>/dev/null
"$DROPBEARKEY" -t ed25519 -f "$OUTDIR/etc/dropbear/dropbear_ed25519_host_key" 2>/dev/null

# --- System files ---
# /etc/passwd - root with password "linux" (openssl hash)
HASH=$(openssl passwd -1 "linux")
cat > "$OUTDIR/etc/passwd" << EOF
root:x:0:0:root:/root:/bin/sh
EOF

cat > "$OUTDIR/etc/shadow" << EOF
root:${HASH}:19769:0:99999:7:::
EOF
chmod 640 "$OUTDIR/etc/shadow"

cat > "$OUTDIR/etc/group" << EOF
root:x:0:
EOF

cat > "$OUTDIR/etc/shells" << EOF
/bin/sh
/bin/ash
EOF

# Minimal nsswitch so getpwnam works
cat > "$OUTDIR/etc/nsswitch.conf" << EOF
passwd: files
group:  files
shadow: files
EOF

# --- Init script ---
cat > "$OUTDIR/init" << 'INITEOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export LD_LIBRARY_PATH=/lib

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /run

# Need /dev/null and /dev/urandom for dropbear
[ -c /dev/null ] || mknod /dev/null c 1 3
[ -c /dev/urandom ] || mknod /dev/urandom c 1 9
[ -c /dev/random ] || mknod /dev/random c 1 8
[ -c /dev/ptmx ] || mknod /dev/ptmx c 5 2
chmod 666 /dev/ptmx 2>/dev/null

# /dev/pts needs proper permissions for SSH PTY allocation
mount -o remount,gid=0,mode=620 /dev/pts 2>/dev/null

echo "========================================="
echo "  Lenovo IdeaCentre Mini x - Test Boot"
echo "  SSH-enabled initramfs"
echo "========================================="

# Wait for block devices
echo "Waiting for block devices..."
sleep 5

# --- Mount USB for logging ---
LOGDIR=""
for dev in /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sda /dev/sdb /dev/sdc \
           /dev/nvme0n1p1 /dev/mmcblk0p1; do
  if [ -b "$dev" ]; then
    echo "Trying to mount $dev..."
    mkdir -p /mnt/usb
    if mount -t vfat "$dev" /mnt/usb 2>/dev/null; then
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
  LOGDIR="/tmp"
fi

# --- Capture hardware data (background, don't block SSH) ---
(
  date > "$LOGDIR/boot-timestamp.txt" 2>/dev/null || true
  dmesg > "$LOGDIR/dmesg.txt" 2>&1
  cat /proc/cpuinfo > "$LOGDIR/cpuinfo.txt" 2>&1
  cat /proc/iomem > "$LOGDIR/iomem.txt" 2>&1
  cat /proc/interrupts > "$LOGDIR/interrupts.txt" 2>&1
  cat /proc/partitions > "$LOGDIR/partitions.txt" 2>&1
  cat /proc/cmdline > "$LOGDIR/cmdline.txt" 2>&1
  cat /proc/modules > "$LOGDIR/modules.txt" 2>&1 || true

  # Device tree
  if [ -d /sys/firmware/devicetree/base ]; then
    ls -laR /sys/firmware/devicetree/base/ > "$LOGDIR/devicetree-listing.txt" 2>&1
    cat /sys/firmware/devicetree/base/compatible > "$LOGDIR/dt-compatible.txt" 2>/dev/null || true
  fi

  # Network
  ip link > "$LOGDIR/ip-link.txt" 2>&1
  ip addr > "$LOGDIR/ip-addr.txt" 2>&1

  # PCI devices
  for pcidev in /sys/bus/pci/devices/*/; do
    vendor=$(cat "${pcidev}vendor" 2>/dev/null)
    device=$(cat "${pcidev}device" 2>/dev/null)
    class=$(cat "${pcidev}class" 2>/dev/null)
    driver=$(readlink "${pcidev}driver" 2>/dev/null)
    driver=${driver##*/}
    echo "${pcidev##*/}: vendor=$vendor device=$device class=$class driver=$driver"
  done > "$LOGDIR/pci-devices.txt" 2>&1

  # USB devices
  for usbdev in /sys/bus/usb/devices/*/; do
    if [ -f "${usbdev}idVendor" ]; then
      vid=$(cat "${usbdev}idVendor" 2>/dev/null)
      pid=$(cat "${usbdev}idProduct" 2>/dev/null)
      prod=$(cat "${usbdev}product" 2>/dev/null)
      mfg=$(cat "${usbdev}manufacturer" 2>/dev/null)
      echo "${usbdev##*/}: vid=$vid pid=$pid product='$prod' manufacturer='$mfg'"
    fi
  done > "$LOGDIR/usb-devices.txt" 2>&1

  # Platform devices
  ls /sys/bus/platform/devices/ > "$LOGDIR/platform-devices.txt" 2>&1

  # ACPI
  ls /sys/firmware/acpi/tables/ > "$LOGDIR/acpi-tables-list.txt" 2>&1 || echo "No ACPI" > "$LOGDIR/acpi-tables-list.txt"

  # Clocks (debugfs)
  if [ -d /sys/kernel/debug ]; then
    mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
    cat /sys/kernel/debug/clk/clk_summary > "$LOGDIR/clk-summary.txt" 2>/dev/null || echo "clk_summary not available" > "$LOGDIR/clk-summary.txt"
  fi

  # Regulators
  for reg in /sys/class/regulator/*/; do
    name=$(cat "${reg}name" 2>/dev/null)
    state=$(cat "${reg}state" 2>/dev/null)
    echo "${reg##*/}: name=$name state=$state"
  done > "$LOGDIR/regulators.txt" 2>&1

  sync
  echo "Hardware capture complete." > "$LOGDIR/capture-done.txt"
) &
echo "Hardware capture running in background..."

# --- Bring up Ethernet ---
echo "Bringing up network..."
ETH_UP=0
for iface in eth0 enp5s0 end0; do
  if ip link set "$iface" up 2>/dev/null; then
    echo "Interface $iface is up, requesting DHCP..."
    if udhcpc -i "$iface" -t 5 -T 3 -n 2>/dev/null; then
      ETH_UP=1
      MY_IP=$(ip -4 addr show "$iface" 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d' ' -f2)
      echo ""
      echo "========================================="
      echo "  NETWORK UP: $iface = $MY_IP"
      echo "========================================="
      # Log IP to USB so it can be read from Windows
      echo "$MY_IP" > "$LOGDIR/ip-address.txt" 2>/dev/null || true
      echo "$iface: $MY_IP" >> "$LOGDIR/ip-address.txt" 2>/dev/null || true
      break
    fi
  fi
done

if [ "$ETH_UP" -eq 0 ]; then
  echo "WARNING: No Ethernet interface came up."
  echo "SSH will not be available. Trying telnetd on serial..."
fi

# --- Start SSH server ---
echo "Starting dropbear SSH server..."
# -R: generate host keys if missing
# -B: allow blank passwords (we have a password set, but just in case)
# -E: log to stderr
# -F: foreground (we background it ourselves)
# -p 22: listen on port 22
/usr/sbin/dropbear -R -E -p 22 2>/dev/null &
DROPBEAR_PID=$!

if [ -n "$MY_IP" ]; then
  echo ""
  echo "========================================="
  echo "  SSH READY"
  echo "  ssh root@${MY_IP}"
  echo "  Password: linux"
  echo "========================================="
  echo ""
  # Also write to USB
  {
    echo "SSH access:"
    echo "  ssh root@${MY_IP}"
    echo "  Password: linux"
  } > "$LOGDIR/ssh-info.txt" 2>/dev/null || true
fi

# Also start telnetd as fallback (no auth, for emergency)
telnetd -l /bin/sh -p 23 2>/dev/null &

echo "Services: SSH on :22, telnet on :23"
echo "Dropping to local shell..."
echo ""

exec /bin/sh
INITEOF
chmod +x "$OUTDIR/init"

# --- Build cpio archive ---
cd "$OUTDIR"
find . | cpio -o -H newc 2>/dev/null | gzip > "$OUTFILE"
echo ""
echo "========================================="
echo "Initramfs built: $(ls -lh "$OUTFILE")"
echo "Root password: linux"
echo "SSH will be available on port 22 after boot"
echo "========================================="
