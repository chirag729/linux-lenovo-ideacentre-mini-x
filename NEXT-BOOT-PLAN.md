# Next Boot Plan: Display Enablement

## Status (2026-02-18)

Boot 6 achieved first interactive Linux session via telnet. Full hardware exploration
complete -- see `testing/boot-logs/2026-02-18-boot6-telnet-interactive/ANALYSIS.md`.

**Current state:** Telnet works, SSH needs /root perms + password fix. System stable (>30min uptime).
Display is intentionally disabled via `drm.modeset=0` + `nomodeset`.

## Overview

Now that we have interactive access and comprehensive hardware data, the next boot
should focus on display enablement -- the biggest remaining blocker for a usable system.

## Pre-Boot Setup (done on Lenovo Windows)

These steps are already complete:
- [x] Kernel built: 6.19.0-rc4 from Mostafa's `lenovo` branch
- [x] DTB: `x1p42100-lenovo-ideacentre-x-gen10.dtb`
- [x] GRUB-EFI USB stick with `devicetree` loading
- [x] Initramfs with busybox + dropbear SSH (2.7MB)
- [x] GRUB boot option 2: DTB + `clk_ignore_unused pd_ignore_unused`

The user needs to copy the new initramfs to the USB before booting:
```powershell
# From admin PowerShell on Lenovo Windows:
Copy-Item "C:\Development\Projects\linux-lenovo-ideacentre-mini-x\usb-staging\initramfs.cpio.gz" -Destination "E:\initramfs.cpio.gz" -Force
```

## Boot Procedure (user does manually)

1. Plug USB stick into Lenovo
2. Disable Secure Boot in BIOS (if re-enabled)
3. Suspend BitLocker: `Suspend-BitLocker -MountPoint "C:" -RebootCount 0`
4. Boot from USB (F12 or change boot order)
5. Select **"2. DTB boot + keep clocks (BEST)"** from GRUB menu
6. Wait ~15 seconds for Ethernet to come up
7. The Lenovo's IP will be written to `E:\logs\ssh-info.txt` (readable after reboot to Windows)
8. Alternatively, check your router's DHCP leases for a new device (MAC: `18:3d:2d:ce:9f:ac`)

## SSH Access

```bash
ssh root@<LENOVO_IP>
# Password: linux
```

The Lenovo's Ethernet MAC is `18:3d:2d:ce:9f:ac` (Realtek RTL8168h, interface `eth0`).
Look for this in your router's DHCP lease table to find the IP.

## What To Do Once Connected

### Priority 1: Verify interactive access works
```bash
uname -a
cat /proc/cpuinfo | head -20
dmesg | tail -50
ip addr show eth0
```

### Priority 2: Deep hardware exploration
```bash
# Full dmesg with DRM/display errors
dmesg | grep -i -E "drm|display|dp|hdmi|mdss|msm|efifb|framebuffer"

# Display subsystem details
ls -la /sys/class/drm/
cat /sys/class/drm/*/status 2>/dev/null
cat /sys/class/drm/*/modes 2>/dev/null
cat /sys/class/drm/*/enabled 2>/dev/null

# DRM driver state
dmesg | grep -i "drm\|msm\|adreno\|dpu\|dsi\|dp " > /mnt/usb/logs/drm-debug.txt

# I2C buses (retimers, display bridges)
ls /sys/bus/i2c/devices/
for dev in /sys/bus/i2c/devices/*/; do
  name=$(cat "${dev}name" 2>/dev/null)
  echo "${dev##*/}: $name"
done

# GPIO state
cat /sys/kernel/debug/gpio 2>/dev/null

# Pinctrl state
cat /sys/kernel/debug/pinctrl/pinctrl-handles 2>/dev/null
cat /sys/kernel/debug/pinctrl/pinctrl-maps 2>/dev/null

# Power domains
ls /sys/kernel/debug/pm_genpd/ 2>/dev/null
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null

# Interconnect state
cat /sys/kernel/debug/interconnect/interconnect_summary 2>/dev/null

# Detailed regulator info
for reg in /sys/class/regulator/*/; do
  name=$(cat "${reg}name" 2>/dev/null)
  state=$(cat "${reg}state" 2>/dev/null)
  uv=$(cat "${reg}microvolts" 2>/dev/null)
  echo "${reg##*/}: name=$name state=$state uV=$uv"
done

# Remoteproc status
for rp in /sys/class/remoteproc/*/; do
  name=$(cat "${rp}name" 2>/dev/null)
  state=$(cat "${rp}state" 2>/dev/null)
  echo "${rp##*/}: name=$name state=$state"
done

# Thermal zones
for tz in /sys/class/thermal/thermal_zone*/; do
  type=$(cat "${tz}type" 2>/dev/null)
  temp=$(cat "${tz}temp" 2>/dev/null)
  echo "${tz##*/}: type=$type temp=${temp}"
done
```

### Priority 3: Display debugging (main goal)
The display goes black after initial efifb works. Need to understand why.

```bash
# Check if efifb is still registered
dmesg | grep efifb

# Check DRM_MSM probe
dmesg | grep -i "msm_drm\|mdss\|dpu\|display-subsystem"

# Check if any DRM connectors are detected
cat /sys/class/drm/*/status 2>/dev/null

# Check DisplayPort controller state
dmesg | grep -i "dp \|displayport\|dp_"

# Check what killed the framebuffer
dmesg | grep -i "unregister\|remove\|disable" | grep -i "fb\|frame\|display"
```

### Priority 4: Save all findings to USB
```bash
# Re-run dmesg capture (will have more data now)
dmesg > /mnt/usb/logs/dmesg-interactive.txt
ip addr > /mnt/usb/logs/ip-addr-interactive.txt

# Save all debug outputs
sync
```

## Boot Debugging History (2026-02-17)

### Boot 3 (v1 initramfs -- original from WSL2)
- DHCP packets sent (router saw MAC at 192.168.1.15), system alive
- **Bug 1:** No `/usr/share/udhcpc/default.script` -- DHCP lease never configures IP
- **Bug 2:** `/lib/ld-linux-aarch64.so.1` symlinks to itself -- dropbear can't load

### Boot 4 (v2 initramfs -- patched on Pi, udhcpc script added)
- Carrier detected in 4s, DHCP lease obtained (192.168.1.15)
- **Bug 1 partially fixed:** udhcpc script used `$mask` (undefined) instead of `$subnet`
- **Bug 2 still present:** ld-linux symlink loop, dropbear still broken
- **Key finding:** System alive at 29.7s -- watchdog is NOT killing the system

### Boot 5 (v3 initramfs -- both bugs fixed, 2026-02-18)
- Fixed ld-linux binary + udhcpc script
- Same errors persisted -- possible initramfs loading mismatch
- Logs: `testing/boot-logs/2026-02-18-boot5-dhcp-ok-ip-missing/`

### Boot 6 (v4 initramfs -- SUCCESS, 2026-02-18)
- Build marker v4-pi-20260218-204435
- DHCP works, IP 192.168.1.15 configured, ping works
- Telnet shell works on port 23 (busybox telnetd)
- SSH (dropbear) connects but rejects: /root perms wrong + password issue
- Full interactive hardware exploration completed via telnet
- System stable for >30 minutes
- Logs + analysis: `testing/boot-logs/2026-02-18-boot6-telnet-interactive/`

## Known Hardware (updated 2026-02-18 from interactive session)

- **Kernel:** 6.19.0-rc4-g740f9e80d577
- **DT model:** "Lenovo IdeaCentre X Gen 10 Snapdragon"
- **DT compatible:** `lenovo,ideacentre-x-gen10`, `qcom,x1p42100`
- **CPU:** 8 Oryon cores (4 perf variant 0x2 + 4 eff variant 0x1), 32GB RAM
- **Ethernet:** RTL8168h, r8169, MAC 18:3d:2d:ce:9f:ac -- **WORKING**
- **NVMe:** Samsung MZVL8512HDLU-00BLL 500GB, FW 9L2QKXD7 -- **WORKING**
- **USB:** 4x xHCI, GL3510 hubs, keyboard (1a2c:2124) -- **WORKING**
- **WiFi:** FastConnect 7800 (17cb:1107) -- no driver bound
- **efifb:** 1920x1080x32 at 0xe4800000 -- **WORKING** (when DRM disabled)

### Display Architecture (from DT + runtime)
- **MDSS:** ae00000.display-subsystem (IOMMU group 5)
- **DPU:** ae01000.display-controller
- **DP controllers (4 in DT!):**
  - `ae90000` (DP0) -- USB-C DP alt mode, uses PHY@fd5000 (USB3/DP combo)
  - `ae98000` (DP2) -- in DT but NOT in platform devices
  - `ae9a000` (DP3) -- in DT but NOT in platform devices
  - `aea0000` (DP1) -- has aux-bus/panel child (eDP?), pinctrl, enable-gpios
- **PHY@fd5000:** USB3/DP combo PHY with orientation-switch + mode-switch (Type-C)
- **Retimers:** ps8830 (Parade DP), ptn3222 (NXP USB-C)
- **Retimer power:** Only RTMR0 enabled; RTMR1, RTMR2, EDP_3P3 all disabled
- **Power:** mdss_gdsc OFF, gpu_cc_* OFF, mmcx ON
- **Clocks:** gcc + gpucc sync_state pending due to GMU (3d6a000.gmu)
- **PMIC glink:** connector@0 can't link to supplier 2-0008 (Type-C mux)

### Missing Firmware
- `qcom/x1e80100/adsp.mbn` -- ADSP (note: x1e80100 path, not x1p42100)
- `qcom/x1e80100/cdsp.mbn` -- CDSP
- `regulatory.db` -- WiFi regulatory
- Missing: wpss.mbn (WiFi subsystem, from first boot)

### Other Issues
- **LPASS pinctrl:** deferred probe -- "Failed to get clk 'core'" (audio)
- **RTC:** deferred probe (unknown reason)
- **USB mouse:** SIGMACHIP 1c4f:0034 reconnects every ~2.5s (faulty mouse)

## Next Boot Plan: Display Enablement

### Pre-Boot Changes (on USB stick)

#### 1. Fix SSH in initramfs
```bash
# In initramfs, fix /root permissions and password:
chmod 0700 /root
chown 0:0 /root
# Set root password in /etc/shadow (or use dropbear -G "" for any group)
```

#### 2. Add GRUB option without nomodeset
Add a new GRUB menu entry that removes `nomodeset` and `drm.modeset=0`:
```
menuentry "3. DRM enabled (display test)" {
    devicetree /dtb/x1p42100-lenovo-ideacentre-x-gen10.dtb
    linux /Image clk_ignore_unused pd_ignore_unused console=tty0 earlycon earlyprintk loglevel=8 keep_bootcon
    initrd /initramfs.cpio.gz
}
```
This lets DRM_MSM probe and try to drive the display.

### What To Do Once Connected (Boot 7+)

#### Priority 1: DRM probe analysis
```bash
# With DRM enabled, capture everything about the display probe:
dmesg | grep -i -E "drm|msm|dpu|dp|mdss|display|adreno|gpu"
cat /sys/class/drm/*/status 2>/dev/null
cat /sys/class/drm/*/modes 2>/dev/null
cat /sys/class/drm/*/enabled 2>/dev/null
cat /sys/kernel/debug/dri/*/state 2>/dev/null
```

#### Priority 2: Understand why only retimer 0 is powered
The DT has 3 retimer sets but only RTMR0 regulators are enabled. This might
be because the kernel only enables regulators for active consumers.

#### Priority 3: Check if efifb survives with DRM enabled
```bash
dmesg | grep -i "efifb\|simpledrm\|framebuffer"
cat /proc/fb
ls /dev/fb*
```

#### Priority 4: Extract firmware from Windows NVMe
```bash
# Mount Windows partition (NTFS, read-only)
mount -t ntfs3 -o ro /dev/nvme0n1p3 /mnt/windows
# Find Qualcomm firmware
find /mnt/windows -name "adsp.mbn" -o -name "cdsp.mbn" -o -name "wpss.mbn" 2>/dev/null
find /mnt/windows -path "*/qcom*" -name "*.mbn" 2>/dev/null
```
