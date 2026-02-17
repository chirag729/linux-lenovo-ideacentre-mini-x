# Next Boot Plan: SSH Interactive Session

## Overview

The Lenovo IdeaCentre Mini x boots Linux from USB but has no working display output.
The initramfs on the USB stick brings up Ethernet and starts an SSH server.
This Claude Code instance (running on an Ubuntu machine on the same LAN) will SSH
into the Lenovo to perform interactive hardware debugging and data capture.

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

## Known Facts from First Boot

- **Kernel:** 6.19.0-rc4-g740f9e80d577
- **DT compatible:** `lenovo,ideacentre-x-gen10 qcom,x1p42100`
- **CPU:** 8 Oryon cores (4 perf + 4 efficiency), 32GB RAM
- **Ethernet:** RTL8168h, r8169 driver, MAC 18:3d:2d:ce:9f:ac -- **WORKING**
- **NVMe:** Samsung 512GB, nvme driver -- **WORKING**
- **USB:** 4x xHCI, GL3510 hubs, keyboard/mouse -- **WORKING**
- **WiFi:** FastConnect 7800 (17cb:1107) -- no driver (needs ath12k firmware)
- **Display:** efifb at e4800000, 2 DP controllers (ae90000, aea0000), 3 retimers -- **BROKEN**
- **Missing firmware:** adsp.mbn, cdsp.mbn, wpss.mbn (remoteprocs not started)
- **Boot cmdline:** `nomodeset video=efifb:on drm.modeset=0 clk_ignore_unused pd_ignore_unused console=tty0 earlycon earlyprintk loglevel=8 keep_bootcon`

## Repo Structure

```
hardware/              # Windows hardware audit data (27 files)
testing/boot-logs/     # Linux boot captures
  2026-02-16-first-boot/  # 19 log files from blind boot
scripts/
  build-initramfs.sh   # Builds the SSH-capable initramfs
  grub.cfg             # GRUB menu with 3 boot options
  update-usb.sh        # Copy initramfs + grub.cfg to staging
  run-qemu.sh          # QEMU test in WSL2
usb-staging/           # Staging area for USB files (gitignored)
PLAN.md                # Full project plan
PROGRESS.md            # Granular progress tracker
CLAUDE.md              # Project instructions for Claude Code
```
