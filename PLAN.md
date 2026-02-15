# Linux on Lenovo IdeaCentre Mini x Gen 10 (Snapdragon X)

## Master Plan

**Target device:** Lenovo IdeaCentre Mini x Gen 10 (91B6) with Snapdragon X X1-26-100
**Primary OS:** Ubuntu (25.04 / 25.10 / 26.04)
**Secondary targets:** Fedora, Arch Linux ARM, Debian
**Goal:** Flawless hardware support, contributed upstream to mainline Linux kernel and distributions

---

## Development Infrastructure

Two physical machines, three Claude Code instances, coordinating via this git repo and the local network.

### Machine 1: Raspberry Pi 5 (always-on server)
- **IP:** 192.168.1.14 (Ethernet)
- **OS:** Ubuntu ARM64, 16GB RAM, NVMe, 8GB swap
- **Primary role:** Always-on infrastructure -- TFTP server, NFS root server, netconsole listener, git origin
- **Secondary role:** Backup build host (4 cores @ 2.4GHz, use `make -j3`, ccache enabled)
- **Claude Code instance:** Coordination, analysis, patch preparation

### Machine 2: Lenovo IdeaCentre Mini x Gen 10 (build host + target)
- **OS:** Windows 11 on ARM + WSL2 (Ubuntu ARM64) + Linux test boots
- **Specs:** 8 cores @ 3.0GHz, 32GB RAM -- our primary build machine via WSL2
- **Claude Code instances:**
  - **Windows (PowerShell):** Hardware data capture, firmware extraction
  - **WSL2 (Ubuntu):** Kernel compilation (`make -j7`, ccache), DTS authoring, DT validation

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│                  Lenovo IdeaCentre Mini x                  │
│                                                            │
│  ┌─────────────────────┐  ┌────────────────────────────┐  │
│  │  Windows 11 ARM      │  │  WSL2 (Ubuntu ARM64)       │  │
│  │                      │  │                            │  │
│  │  - HW data capture   │  │  - PRIMARY BUILD HOST      │  │
│  │  - Firmware extract   │  │  - make -j7 (8c, 32GB)    │  │
│  │  - Claude Code (PS)   │  │  - DTS authoring           │  │
│  │                      │  │  - DT validation            │  │
│  │                      │  │  - Writes to EFI partition  │  │
│  │                      │  │    via /mnt/c/              │  │
│  │                      │  │  - Claude Code (bash)       │  │
│  └──────────────────────┘  └────────────────────────────┘  │
│                                                            │
│  [Reboot into Linux for testing]                           │
│  - Boots kernel from EFI partition (written by WSL2)       │
│  - OR network boots via TFTP from Pi                       │
│  - Debug via: netconsole → Pi, SSH over Ethernet → Pi      │
└────────────────────┬─────────────────────────────────────┘
                     │ Ethernet (192.168.1.x)
                     │
┌────────────────────┴─────────────────────────────────────┐
│                  Raspberry Pi 5 (192.168.1.14)             │
│                                                            │
│  - TFTP server: serves kernel Image + DTB                  │
│  - NFS server: serves root filesystem                      │
│  - netconsole listener: captures Lenovo boot output        │
│  - Always-on (never reboots)                               │
│  - Git repo origin                                         │
│  - Backup build host (make -j3, ccache)                    │
│  - Claude Code (analysis, coordination, patch prep)        │
└──────────────────────────────────────────────────────────┘
```

### Build Speed Comparison

| | Pi 5 | Lenovo WSL2 |
|--|------|-------------|
| Cores | 4 @ 2.4GHz | 8 @ 3.0GHz |
| RAM | 16GB (+8GB swap) | 32GB |
| Full kernel build | ~60-90 min | ~15-25 min |
| Incremental (with ccache) | ~5-15 min | ~2-5 min |
| DTS-only rebuild | seconds | seconds |
| Available during test boot | Yes | No (rebooting) |

**Primary build on WSL2. Fall back to Pi when Lenovo is rebooted for testing.**

### Debug Access (No Display)

Display output is broken initially. These methods provide console access without a working display, in order of preference:

1. **netconsole** (kernel console over Ethernet UDP)
   - Add to kernel cmdline: `netconsole=@/eth0,6666@192.168.1.14/`
   - Pi listens: `nc -u -l -p 6666 | tee testing/boot-logs/$(date +%Y%m%d-%H%M).txt`
   - Zero setup on Lenovo side, just a cmdline parameter
   - Works from earliest kernel boot, before rootfs mounts

2. **SSH over Ethernet**
   - Rootfs runs sshd on boot, Pi connects via `ssh root@<lenovo-ip>`
   - Interactive shell for testing, requires Ethernet driver working + rootfs
   - Add a static IP fallback in the rootfs: `ip=192.168.1.100::192.168.1.1:255.255.255.0::eth0:off`

3. **Blind boot + capture script**
   - `hardware-audit.sh` runs on boot, writes everything to a partition
   - Slowest iteration (requires reboot + mount USB/partition to read results)
   - Reliable fallback if network doesn't work

### Data Flow

```
WSL2 builds kernel
  → writes Image + DTB to EFI partition (/mnt/c/efi/ or similar)
  → OR: rsync to Pi TFTP directory (rsync -av Image pi@192.168.1.14:/srv/tftp/)
  → commits DTS/defconfig changes to git repo

Lenovo reboots into Linux
  → boots from EFI partition or TFTP
  → netconsole streams boot log to Pi in real-time
  → SSH available once Ethernet + rootfs are up
  → test results captured

Pi receives
  → netconsole log saved to testing/boot-logs/
  → SSH session used for interactive testing
  → results committed to git repo
  → analysis fed back into DTS/kernel changes
```

### Network Boot Setup (Pi 5)

Set up once, used for all subsequent test iterations:

**TFTP** (serves kernel + DTB):
```bash
sudo apt install tftpd-hpa
# Config: /etc/default/tftpd-hpa → TFTP_DIRECTORY="/srv/tftp"
sudo mkdir -p /srv/tftp
# After each build, copy files:
# cp Image x1p42100-lenovo-ideacentre-mini-x.dtb /srv/tftp/
```

**NFS** (serves root filesystem):
```bash
sudo apt install nfs-kernel-server
sudo mkdir -p /srv/nfs/lenovo-rootfs
# Populate with a minimal Ubuntu ARM64 rootfs (debootstrap)
# /etc/exports: /srv/nfs/lenovo-rootfs *(rw,no_root_squash,no_subtree_check)
sudo exportfs -ra
```

**netconsole listener:**
```bash
# Run on Pi to capture Lenovo boot output:
nc -u -l -p 6666 | tee testing/boot-logs/$(date +%Y%m%d-%H%M).txt
```

---

## Current State of Play

Mostafa Saleh (Google) has done initial bring-up work:
- **Repository:** https://github.com/misaleh/linux/tree/lenovo
- **Based on:** Linux 6.13-rc4, using `x1p42100-crd.dts` as a starting point
- **Working:** Boot to shell, serial console, NVMe, WiFi detection, PCIe, single USB-C port, EL2 boot
- **Broken:** Display output (DPU vblank timeouts), audio (probe error -22), additional USB/DP ports not mapped, system crashes after reaching userspace (suspected watchdog timeout)
- **DTS file created:** `x1p42100-lenovo-ideacentre-x-gen10.dts` (1,845 lines, derived from CRD reference)

No upstream patches have been submitted. No DTBLoader support exists. The Ubuntu Concept ISO does not include this device.

---

## Hardware Summary

| Component | Detail | Linux Driver | Status |
|-----------|--------|-------------|--------|
| SoC | Snapdragon X X1-26-100 (Purwa die, 8-core Oryon) | `x1p42100.dtsi` | Base SoC DTSI exists upstream |
| GPU | Adreno X1-45, 1.7 TFLOPS | `msm` DRM / freedreno / Turnip | GPU nodes MISSING from x1p42100.dtsi |
| NPU | Hexagon, 45 TOPS | No mainline driver | Not targeted initially |
| RAM | 32GB LPDDR5x-8448 (soldered) | N/A | Works |
| NVMe | 2x M.2 2280 PCIe 4.0 x4 | `nvme` | Working |
| WiFi | Qualcomm FastConnect 7800 (WCN7850-class) | `ath12k` | Detected, needs firmware |
| Bluetooth | Integrated with WiFi module | `ath12k` / `btusb` | Not working on most X1P devices |
| Ethernet | Gigabit (controller TBD) | TBD (likely Realtek) | Detected, needs identification |
| Audio | WCD9385 codec + WSA8845 speakers | `snd-soc-qcom` | Probe failure (-22) |
| USB-C front | USB 3.2 Gen 2 (10Gbps) | `dwc3` | Partially working |
| USB-A front | USB 3.2 Gen 2 (10Gbps, always-on) | `dwc3` / `xhci` | Needs mapping |
| USB-C rear | USB4 (40Gbps) + DP 1.4a alt-mode | `dwc3` / `typec` | Partially working |
| USB-A rear | 2x USB 3.2 Gen 2 + 1x USB 2.0 | `dwc3` / `xhci` | Needs mapping |
| HDMI | HDMI 2.1 TMDS | `msm` DRM | Not mapped |
| DisplayPort | DP 1.4a (dedicated) | `msm` DRM | Not mapped (removed from DTS) |
| Power | 150W internal PSU | N/A | N/A |
| TPM | Firmware TPM 2.0 | `tpm_ftpm_tee` | Unknown |

---

## Phase 0: Prerequisites & Environment Setup

### 0.1 Acquire the Hardware
- [ ] Obtain a Lenovo IdeaCentre Mini x Gen 10 unit (or confirm already available)
- [ ] Ensure Windows 11 on ARM is installed and fully updated (needed for firmware extraction and ACPI/SMBIOS data collection)
- [ ] Install Claude Code on the Lenovo (Windows PowerShell) -- hardware data capture agent
- [ ] Install WSL2 on the Lenovo -- primary build host:
  ```powershell
  wsl --install -d Ubuntu
  ```
- [ ] Install Claude Code inside WSL2 -- primary build agent
- [ ] Optional: USB-to-UART serial adapter (3.3V) as backup debug channel

### 0.2 Document the Hardware from Windows (Lenovo Claude instance)

The Claude Code instance on the Lenovo runs all of these automatically and commits results to `hardware/` in this repo.

**Scripts to run on Lenovo (PowerShell):**

- [ ] **DMI/SMBIOS data** → `hardware/dmi-data.txt`:
  ```powershell
  Get-WmiObject Win32_BaseBoard | Format-List *
  Get-WmiObject Win32_ComputerSystem | Format-List *
  Get-WmiObject Win32_BIOS | Format-List *
  Get-CimInstance Win32_Processor | Format-List *
  ```
- [ ] **PnP device enumeration** → `hardware/pnp-devices.txt`:
  ```powershell
  Get-PnpDevice | Where-Object {$_.Status -eq 'OK'} | Format-Table -AutoSize
  Get-PnpDevice | Select-Object Class, FriendlyName, InstanceId, Status | Format-Table -AutoSize
  ```
- [ ] **PCI device hardware IDs** → `hardware/pci-devices.txt`:
  ```powershell
  Get-PnpDevice -Class 'Net','Display','Media','USB','System' |
    Get-PnpDeviceProperty -KeyName DEVPKEY_Device_HardwareIds |
    Select-Object InstanceId, Data | Format-List
  ```
- [ ] **Network adapters (WiFi/BT/Ethernet IDs)** → `hardware/network-adapters.txt`:
  ```powershell
  Get-NetAdapter | Format-List *
  Get-NetAdapterHardwareInfo | Format-List *
  ```
- [ ] **USB controller topology** → `hardware/usb-topology.txt`:
  ```powershell
  Get-PnpDevice -Class USB | Format-Table InstanceId, FriendlyName, Status
  ```
- [ ] **Display adapters and monitors** → `hardware/display-info.txt`:
  ```powershell
  Get-PnpDevice -Class Display | Format-List *
  Get-CimInstance Win32_VideoController | Format-List *
  ```
- [ ] **Audio devices** → `hardware/audio-info.txt`:
  ```powershell
  Get-PnpDevice -Class AudioEndpoint | Format-List *
  Get-PnpDevice -Class Media | Format-List *
  ```
- [ ] **Firmware/BIOS version** → `hardware/firmware-info.txt`:
  ```powershell
  Get-CimInstance Win32_BIOS | Format-List *
  ```
- [ ] **Partition layout** → `hardware/partition-layout.txt`:
  ```powershell
  Get-Partition | Format-Table DiskNumber, PartitionNumber, Type, Size, Offset -AutoSize
  Get-Disk | Format-List *
  ```
- [ ] **ACPI tables:** Extract using `acpidump.exe` (from ACPICA tools for Windows ARM64) → `hardware/acpi-tables/`
- [ ] **Secure Boot state** → `hardware/secureboot-info.txt`:
  ```powershell
  Confirm-SecureBootUEFI
  Get-SecureBootPolicy | Format-List *
  ```

### 0.3 Set Up Primary Build Host (Lenovo WSL2)

WSL2 on the Lenovo is our primary build environment: 8 cores, 32GB RAM, native ARM64.

- [ ] Inside WSL2, install build dependencies:
  ```bash
  sudo apt install build-essential flex bison libssl-dev libelf-dev bc \
    ccache device-tree-compiler python3-dtschema yamllint git
  ```
- [ ] Configure ccache:
  ```bash
  echo 'export PATH="/usr/lib/ccache:$PATH"' >> ~/.bashrc
  ccache --max-size=10G
  ```
- [ ] Clone mainline kernel:
  ```bash
  git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git ~/kernel/linux
  ```
- [ ] Clone Mostafa's fork for reference:
  ```bash
  git clone -b lenovo https://github.com/misaleh/linux.git ~/kernel/misaleh-linux
  ```
- [ ] Clone this project repo and dtbloader:
  ```bash
  git clone <this-repo-url> ~/Projects/lenovo-mini-ubuntu
  git clone https://github.com/TravMurav/dtbloader.git ~/kernel/dtbloader
  ```
- [ ] Verify build works:
  ```bash
  cd ~/kernel/linux && make defconfig && make -j7 Image
  ```
- [ ] Verify WSL2 can access the Windows EFI partition (for placing kernel images):
  ```bash
  ls /mnt/c/  # Should see Windows C: drive
  ```

### 0.4 Set Up Pi 5 as Server

The Pi is always-on infrastructure: TFTP, NFS, netconsole listener, git origin.

- [ ] Install server packages and build tools:
  ```bash
  sudo apt install build-essential flex bison libssl-dev libelf-dev bc \
    ccache device-tree-compiler \
    tftpd-hpa nfs-kernel-server minicom screen
  ```
- [ ] Configure ccache:
  ```bash
  echo 'export PATH="/usr/lib/ccache:$PATH"' >> ~/.bashrc
  ccache --max-size=10G
  ```
- [ ] Clone kernel sources (backup build host):
  ```bash
  git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git ~/kernel/linux
  git clone -b lenovo https://github.com/misaleh/linux.git ~/kernel/misaleh-linux
  git clone https://github.com/TravMurav/dtbloader.git ~/kernel/dtbloader
  ```
- [ ] Set up TFTP server:
  ```bash
  sudo mkdir -p /srv/tftp
  # Edit /etc/default/tftpd-hpa: TFTP_DIRECTORY="/srv/tftp"
  sudo systemctl enable --now tftpd-hpa
  ```
- [ ] Set up NFS root filesystem:
  ```bash
  sudo mkdir -p /srv/nfs/lenovo-rootfs
  # Populate with minimal Ubuntu ARM64 rootfs via debootstrap
  # Add to /etc/exports: /srv/nfs/lenovo-rootfs *(rw,no_root_squash,no_subtree_check)
  sudo exportfs -ra
  sudo systemctl enable --now nfs-kernel-server
  ```
- [ ] Set up git remote for this repo that the Lenovo WSL2 instance can access

### 0.5 Preserve the Windows Partition
- [ ] **Do NOT wipe Windows.** Shrink the Windows partition to make room for Linux
- [ ] WSL2 lives inside the Windows partition -- it needs Windows running
- [ ] Firmware blobs must be extracted from the Windows partition using `qcom-firmware-extract`
- [ ] The DPP partition must remain intact (contains WiFi/BT calibration data)
- [ ] The Windows installation remains useful as a reference environment and for firmware updates

---

## Phase 1: Hardware Audit & Identification

**Goal:** Fully identify every hardware component and its Linux driver requirements.

This phase uses BOTH machines. The Lenovo (Windows) instance captures data that Windows exposes well (PnP IDs, driver info, ACPI), while the Pi analyzes it and correlates with Linux kernel source.

### 1.1 Windows-Side Hardware Audit (Lenovo Claude instance)

These commands are run by the Claude Code instance on the Lenovo and committed to `hardware/`:

- [ ] Run all Phase 0.2 PowerShell scripts and commit results
- [ ] **Detailed PCI enumeration** → `hardware/pci-detailed.txt`:
  ```powershell
  # Get all PCI devices with full hardware IDs and location info
  Get-PnpDevice | Where-Object {$_.InstanceId -like 'PCI*'} |
    ForEach-Object {
      $_ | Format-List InstanceId, FriendlyName, Class, Status
      $_ | Get-PnpDeviceProperty -KeyName DEVPKEY_Device_HardwareIds,
        DEVPKEY_Device_LocationInfo, DEVPKEY_Device_Driver |
        Format-List
    }
  ```
- [ ] **USB tree with physical port mapping** → `hardware/usb-detailed.txt`:
  ```powershell
  Get-PnpDevice | Where-Object {$_.InstanceId -like 'USB*'} | Format-List *
  ```
- [ ] **ACPI device enumeration** → `hardware/acpi-devices.txt`:
  ```powershell
  Get-PnpDevice | Where-Object {$_.InstanceId -like 'ACPI*'} |
    Select-Object InstanceId, FriendlyName, Status | Format-Table -AutoSize
  ```
- [ ] **Display topology** (identify bridge chips, MST hubs):
  ```powershell
  Get-CimInstance Win32_VideoController | Format-List *
  Get-CimInstance Win32_DesktopMonitor | Format-List *
  ```
- [ ] **Run `msinfo32 /report hardware/msinfo32-report.txt`** -- comprehensive system information report

### 1.2 Linux-Side Hardware Audit (after first Linux boot)

Build Mostafa's kernel on WSL2 (fast), set up netconsole on the Pi (always-on), and boot the Lenovo:

- [ ] Build Mostafa's kernel from the `lenovo` branch on WSL2:
  ```bash
  cd ~/kernel/misaleh-linux
  make qcom_defconfig
  make -j7 Image dtbs
  ```
- [ ] Place kernel + DTB on bootable USB or EFI partition (WSL2 can write to `/mnt/c/`)
- [ ] Start netconsole listener on Pi:
  ```bash
  nc -u -l -p 6666 | tee testing/boot-logs/$(date +%Y%m%d-%H%M)-audit.txt
  ```
- [ ] Add netconsole to kernel cmdline: `netconsole=@/eth0,6666@192.168.1.14/`
- [ ] Reboot Lenovo into Linux -- Pi captures boot log in real time
- [ ] If Ethernet + rootfs work, SSH in from Pi for interactive testing
- [ ] **Create an auto-capture script** that runs at boot and saves everything to a USB partition:
  ```bash
  #!/bin/bash
  # hardware-audit.sh -- runs automatically and saves to /mnt/capture/
  dmesg > /mnt/capture/dmesg.txt
  cat /proc/cpuinfo > /mnt/capture/cpuinfo.txt
  cat /proc/iomem > /mnt/capture/iomem.txt
  cat /proc/interrupts > /mnt/capture/interrupts.txt
  lspci -vvnn > /mnt/capture/lspci.txt 2>&1
  lsusb -t > /mnt/capture/lsusb-tree.txt 2>&1
  lsusb -v > /mnt/capture/lsusb-verbose.txt 2>&1
  find /proc/device-tree/ -type f | head -500 > /mnt/capture/dt-nodes.txt
  ls -la /sys/class/regulator/ > /mnt/capture/regulators.txt
  ls -la /sys/class/thermal/ > /mnt/capture/thermal-zones.txt
  dmidecode > /mnt/capture/dmidecode.txt 2>&1
  cat /sys/firmware/devicetree/base/model > /mnt/capture/dt-model.txt 2>&1
  cat /sys/firmware/devicetree/base/compatible > /mnt/capture/dt-compatible.txt 2>&1
  # Copy ACPI tables if present
  cp -r /sys/firmware/acpi/tables/ /mnt/capture/acpi-tables/ 2>/dev/null
  ```
- [ ] Bring USB stick back to Pi, commit all captured data to `hardware/linux-audit/`

### 1.3 Analysis (Pi Claude instance)

Once both Windows and Linux data are committed:

- [ ] **Cross-reference** Windows PnP device IDs with Linux `lspci` output
- [ ] **Identify the Ethernet controller** -- match PCI VID:PID to a Linux driver
- [ ] **Map USB topology** -- correlate Windows USB tree with Linux USB tree to identify hub chips
- [ ] **Identify display bridge chips** -- match display PCI/I2C devices to known bridge drivers
- [ ] **Identify retimer chips** -- match I2C device addresses to Parade/ITE/NXP retimer drivers
- [ ] **Compare ACPI tables** from Windows against DT nodes to find missing hardware descriptions
- [ ] **Produce `hardware/hardware-map.md`** -- the definitive component-to-driver mapping

### 1.4 Identify Unknowns
From the research, these components need specific identification:
- [ ] **Ethernet controller:** Exact chipset (Realtek? Intel? Qualcomm?) -- critical for driver selection
- [ ] **USB hub/controller topology:** The IdeaCentre has 6 USB ports but the DTS only maps 1 USB-C. Need to identify the USB hub chips and how they connect to the SoC's USB controllers
- [ ] **Display output routing:** HDMI 2.1 and DP 1.4a outputs likely go through DP-to-HDMI bridges or MST hubs. Identify the bridge chips (likely Parade, ITE, or Analogix)
- [ ] **Retimer chips:** Parade PS8830 is in the CRD DTS. Confirm which retimers are actually present on the IdeaCentre and which I2C buses they sit on
- [ ] **Power sequencing:** Identify how regulators map to real power domains
- [ ] This document becomes the specification for the device tree

---

## Phase 2: Device Tree Development

**Goal:** Create a correct, complete device tree for the Lenovo IdeaCentre Mini x.

### 2.1 Start from the Right Base
- [ ] Determine whether to base on `x1p42100-crd.dts` or start fresh from `x1p42100.dtsi`
- [ ] Mostafa's DTS inlined the CRD DTSI for easier review. For upstream, the final version should use proper `#include` hierarchy
- [ ] Decide: does the IdeaCentre Mini x use the X1-26-100 (base Snapdragon X) or the X1P-42-100 (Snapdragon X Plus)? The product page lists both SKUs. If the Purwa die variant differs from X1P42100 at the DTS level, a new base DTSI may be needed

### 2.2 Create the Board DTS
File: `arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-mini-x.dts`

**Note on naming:** The upstream convention is `$soc-$vendor-$device.dts`. The exact name should follow existing patterns (e.g., `x1e80100-lenovo-yoga-slim7x.dts`). Mostafa used `x1p42100-lenovo-ideacentre-x-gen10.dts`.

Required nodes to define or enable:

#### CPU & Clock
- [ ] Verify CPU topology matches (8 Oryon cores, 2 clusters of 4)
- [ ] Verify clock controller compatible strings for Purwa die
- [ ] Set CPU frequency tables if different from CRD

#### PCIe
- [ ] **PCIe slot 1:** First NVMe M.2 (PCIe 4.0 x4)
- [ ] **PCIe slot 2:** Second NVMe M.2 (PCIe 4.0 x4)
- [ ] **PCIe for WiFi:** Qualcomm WCN7850 on dedicated PCIe lane
- [ ] **PCIe for Ethernet:** Map the Ethernet controller's PCIe connection
- [ ] Verify all PERST# and WAKE# GPIOs from hardware audit

#### USB
- [ ] **USB4/USB-C rear port:** Full USB4 + DP alt-mode, with correct retimer
- [ ] **USB-C front port:** USB 3.2 Gen 2
- [ ] **USB-A rear ports:** 2x USB 3.2 Gen 2 + 1x USB 2.0
- [ ] **USB-A front port:** USB 3.2 Gen 2 (Always On)
- [ ] Map the USB hub chips that fan out from the SoC's USB controllers
- [ ] Define orientation switch GPIOs for USB-C ports
- [ ] Define power delivery for USB ports

#### Display
- [ ] **HDMI 2.1:** Identify the DP-to-HDMI bridge chip, add I2C/GPIO nodes
- [ ] **DisplayPort 1.4a:** Direct DP output from SoC or via retimer
- [ ] **USB-C DP alt-mode:** DP output through the rear USB4 port
- [ ] Configure MDSS (Mobile Display Subsystem) for external-only display
- [ ] **Remove eDP panel node** -- the CRD DTS has an internal panel defined. The IdeaCentre is a desktop with no built-in display

#### Audio
- [ ] **WCD9385 codec:** SoundWire connection, verify I2C address
- [ ] **Headphone jack:** 3.5mm combo jack on front panel
- [ ] **Remove WSA8845 speaker nodes** unless there's an internal speaker (there shouldn't be in a desktop)
- [ ] Fix the audio machine driver compatible string (the -22 probe error suggests a mismatch)

#### WiFi & Bluetooth
- [ ] **ath12k WiFi:** PCIe device node with correct firmware path
- [ ] **Bluetooth:** Tied to WiFi module, needs correct transport configuration
- [ ] Reference firmware extraction path

#### Ethernet
- [ ] Add the Ethernet controller node based on hardware audit findings
- [ ] If it's a standard PCIe NIC (e.g., Realtek 8111), it may "just work" once PCIe is correct

#### Power & Regulators
- [ ] Define all voltage regulators (RPMH, fixed, GPIO-controlled)
- [ ] Map regulator consumers to hardware nodes
- [ ] Verify regulator voltages against hardware specifications

#### Thermal
- [ ] Define thermal zones for the dual-fan cooling system
- [ ] Set trip points appropriate for a desktop (can be more aggressive than laptop)
- [ ] Configure fan control nodes if accessible

#### Miscellaneous
- [ ] **TPM 2.0:** Enable firmware TPM node
- [ ] **Watchdog:** Ensure watchdog timer is properly configured (suspected cause of the userspace crash)
- [ ] **RTC:** Real-time clock configuration
- [ ] **LED indicators:** Power LED, if controllable
- [ ] Set `chassis-type = "desktop"` (Mostafa already did this)

### 2.3 Validate the Device Tree
- [ ] `make CHECK_DTBS=y dt_binding_check` -- schema validation
- [ ] `make dtbs` -- compile to binary
- [ ] `fdtdump` the output `.dtb` and manually verify node structure
- [ ] Compare against `lspci`/`lsusb`/`dmesg` output from Phase 1

### 2.4 Iterative Testing
- [ ] Boot with new DTS on hardware
- [ ] Compare `dmesg` output against expected node bindings
- [ ] For each subsystem: verify the correct driver probes and reports success
- [ ] Document any driver probe failures with full error context

---

## Phase 3: GPU Enablement

**Goal:** Get display output working through HDMI and DisplayPort.

This is the highest-priority subsystem after basic boot -- a desktop is useless without display output.

### 3.1 Understand the GPU Gap
- [ ] The `x1p42100.dtsi` (Purwa) currently has **no GPU or GMU nodes**
- [ ] The X1E80100 (Hamoa) `x1e80100.dtsi` has full GPU definitions
- [ ] The Purwa die has a smaller Adreno X1-45 GPU with different compatible strings
- [ ] Determine what changes are needed to add GPU support to `x1p42100.dtsi` / `purwa.dtsi`

### 3.2 Add GPU Nodes
- [ ] Add Adreno GPU node to the Purwa DTSI with correct compatible string
- [ ] Add GMU (Graphics Microcontroller Unit) node
- [ ] Configure GPU power domains and clock references
- [ ] Set GPU shader firmware path (`gen70500_zap.mbn` or equivalent for X1-45)
- [ ] Verify OPP (Operating Performance Points) table for the smaller GPU

### 3.3 Display Output Configuration
- [ ] Identify and configure MDSS DP outputs for HDMI and DisplayPort
- [ ] Add DP-to-HDMI bridge driver nodes (if a bridge chip is used)
- [ ] Test each display output individually:
  - [ ] HDMI at various resolutions (1080p, 4K@60, 4K@120)
  - [ ] DisplayPort at various resolutions
  - [ ] USB-C DP alt-mode
  - [ ] Multi-monitor configurations

### 3.4 Mesa/Userspace
- [ ] Ensure Mesa version is >= 25.2 for freedreno support
- [ ] Test OpenGL (freedreno Gallium3D) and Vulkan (Turnip)
- [ ] Verify compositing works (Wayland and X11)
- [ ] Test video decode acceleration if available

---

## Phase 4: Peripheral Driver Enablement

**Goal:** Get all remaining peripherals working.

### 4.1 Audio
- [ ] Debug the probe error (-22) in the audio machine driver
- [ ] The `snd-x1e80100` machine driver may need updates for X1P42100
- [ ] Alternatively, a new machine driver may be needed: `snd-x1p42100`
- [ ] Verify WCD9385 codec initializes over SoundWire
- [ ] Test headphone jack output and microphone input
- [ ] For a desktop without speakers, headphone/line-out is the primary audio path

### 4.2 WiFi
- [ ] Extract firmware from Windows partition using `qcom-firmware-extract`
- [ ] Verify `ath12k` driver loads and associates with an access point
- [ ] Test 2.4GHz, 5GHz, and 6GHz bands
- [ ] Check for the 5GHz regression present in kernel 6.17
- [ ] Test WiFi 7 (802.11be) operation if supported by the driver

### 4.3 Bluetooth
- [ ] Identify the BT transport (typically via QCA UART or USB)
- [ ] Test BT discovery, pairing, and audio (A2DP, HFP)
- [ ] This is known to be broken on most Snapdragon X devices -- may require upstream patches

### 4.4 Ethernet
- [ ] Identify controller from Phase 1 hardware audit
- [ ] Ensure driver is enabled in kernel config
- [ ] Test gigabit throughput
- [ ] Test Wake-on-LAN if supported

### 4.5 USB (Complete Port Mapping)
- [ ] Map all 6 physical USB ports to SoC controllers
- [ ] Test USB storage, HID devices, USB audio on each port
- [ ] Test USB4 bandwidth on rear USB-C port
- [ ] Test "Always On" charging on front USB-A port
- [ ] Verify hot-plug on all ports

### 4.6 Thermal & Fan Control
- [ ] Verify thermal zone readings (`/sys/class/thermal/`)
- [ ] Test fan speed control under load
- [ ] Stress test with no thermal throttling failures
- [ ] Ensure the watchdog doesn't trigger during normal operation

### 4.7 Suspend/Resume
- [ ] Test S3 (suspend to RAM) and S0ix (modern standby)
- [ ] Verify all peripherals resume correctly
- [ ] Test wake sources (USB keyboard, WoL, power button)

---

## Phase 5: Firmware Packaging

**Goal:** Make firmware available without requiring a Windows partition long-term.

### 5.1 Document Firmware Requirements
- [ ] List every firmware blob needed (GPU, WiFi, BT, audio DSP, modem)
- [ ] Document the exact file paths expected by each driver
- [ ] Note which firmware is redistributable vs. requires extraction

### 5.2 Firmware Extraction (Lenovo Claude instance, from Windows)
- [ ] Run `qcom-firmware-extract` on the Lenovo's Windows partition
- [ ] Commit the firmware manifest (file list, sizes, hashes) to `firmware/firmware-manifest.txt`
- [ ] **Do NOT commit the firmware blobs themselves** to the git repo (they are proprietary)
- [ ] Document the extraction process step by step in `firmware/extract.sh`
- [ ] Verify extracted firmware files match what the Linux drivers expect
- [ ] Create a script to automate placement of firmware files into `/lib/firmware/`

### 5.3 Push for Upstream Firmware
- [ ] Check which firmware blobs are already in `linux-firmware.git`
- [ ] For missing firmware, work with Qualcomm/Lenovo to get redistribution permission
- [ ] Submit firmware to `linux-firmware.git` where possible
- [ ] The Lenovo ThinkPad T14s Gen 6 is the only device with upstream firmware -- use that as a precedent

---

## Phase 6: DTBLoader Integration

**Goal:** Enable automatic DTB selection so standard distro ISOs can boot.

### 6.1 Generate Device Description
- [ ] Boot into Linux (or Windows) and run dtbloader's `scripts/describe_hw.sh`
- [ ] This generates SMBIOS/DMI-based hardware IDs (GUIDs)
- [ ] Create `src/devices/lenovo_ideacentre_mini_x.c` in the dtbloader repo

### 6.2 Build and Test DTBLoader
- [ ] Compile dtbloader with the new device definition
- [ ] Install on ESP partition
- [ ] Verify it correctly selects `x1p42100-lenovo-ideacentre-mini-x.dtb`
- [ ] Test boot flow: UEFI -> dtbloader -> systemd-boot -> kernel

### 6.3 Upstream to DTBLoader
- [ ] Submit PR to https://github.com/TravMurav/dtbloader
- [ ] Include the device definition and any Qualcomm DPP fixups for WiFi/BT MAC addresses

---

## Phase 7: Distribution Integration

### 7.1 Ubuntu (Primary Target)

#### Ubuntu Concept ISO
- [ ] Engage with the Ubuntu Concept team on Discourse: https://discourse.ubuntu.com/t/ubuntu-concept-snapdragon-x-elite/48800
- [ ] Submit the device tree for inclusion in the `linux-qcom-x1e` kernel package
- [ ] Test the Ubuntu Concept ISO with the custom DTB
- [ ] File/update bug #2136311 with working DTS and boot instructions

#### Ubuntu Mainline
- [ ] Target Ubuntu 25.10 or 26.04 for out-of-box support
- [ ] The device tree must be in the upstream kernel first (see Phase 8)
- [ ] Work with Canonical's ARM64 team to include DTB in the generic arm64 kernel
- [ ] Test the standard Ubuntu arm64 ISO once DTB is merged

#### Ubuntu Stubble
- [ ] Ubuntu 25.10 introduces "Stubble" which embeds DTBs in the kernel image
- [ ] Once the DTB is upstream, it should automatically be included in Stubble builds
- [ ] Verify Stubble correctly selects the IdeaCentre DTB

### 7.2 Fedora
- [ ] Fedora 42 has an active Snapdragon X bring-up effort
- [ ] Engage at: https://discussion.fedoraproject.org/t/snapdragon-x-elite-fedora-42-system-bring-up-and-looking-for-collaborators-or-sigs/153631
- [ ] Once the DTB is upstream, Fedora's ARM64 kernel should pick it up
- [ ] Test Fedora Workstation arm64 ISO

### 7.3 Arch Linux ARM
- [ ] Arch Linux ARM community is active on Snapdragon X
- [ ] Package the kernel + DTS as an AUR package or custom repo during development
- [ ] Once upstream, Arch's `linux-aarch64` package picks it up automatically

### 7.4 Debian
- [ ] Debian ARM64 support follows upstream kernel closely
- [ ] Once merged upstream, Debian Testing/Unstable will pick up the DTB
- [ ] Engage with Debian ARM porters if needed

### 7.5 Other Distributions
- [ ] openSUSE Tumbleweed (tracks upstream kernel closely)
- [ ] NixOS (ARM64 support is growing)
- [ ] postmarketOS (tracks Qualcomm devices actively)

---

## Phase 8: Upstream Contribution

**Goal:** Get all work merged into mainline Linux so it ships in official distributions.

### 8.1 Prepare Patch Series

The patches should be structured as follows:

1. **dt-bindings: arm: qcom: Add Lenovo IdeaCentre Mini x Gen 10**
   - Update `Documentation/devicetree/bindings/arm/qcom.yaml`
   - Add the compatible string `lenovo,ideacentre-mini-x-gen10`

2. **arm64: dts: qcom: x1p42100: Add GPU and display support** (if needed)
   - Add Adreno GPU, GMU, MDSS nodes to `x1p42100.dtsi` / `purwa.dtsi`
   - This benefits ALL X1P42100 devices, not just the IdeaCentre

3. **arm64: dts: qcom: Add Lenovo IdeaCentre Mini x Gen 10**
   - The board-specific DTS file
   - Makefile entry

4. **Any driver patches** required for the IdeaCentre's specific hardware
   - Audio machine driver updates
   - USB hub/controller support
   - Display bridge driver additions

### 8.2 Submit to Mailing Lists
- [ ] Run `scripts/get_maintainer.pl` on each patch to identify recipients
- [ ] Primary lists: `linux-arm-msm@vger.kernel.org`, `devicetree@vger.kernel.org`
- [ ] CC: Bjorn Andersson, Konrad Dybcio (Qualcomm DT maintainers)
- [ ] CC: Rob Herring, Krzysztof Kozlowski (DT binding maintainers)
- [ ] Use `git send-email` with proper formatting

### 8.3 Validation Before Submission
- [ ] `make CHECK_DTBS=y` -- no warnings
- [ ] `make dtbs_check` -- schema validation passes
- [ ] `scripts/checkpatch.pl` -- no style violations
- [ ] Tested on actual hardware with documented results
- [ ] Patch series builds cleanly on mainline

### 8.4 Review Cycle
- [ ] Respond to review feedback promptly (typically 1-2 week cycles)
- [ ] Rebase on latest mainline if needed
- [ ] Version patches (v2, v3, etc.) with changelog in cover letter
- [ ] Expected timeline: 1-3 kernel release cycles to merge (3-9 months)

### 8.5 linux-firmware Submissions
- [ ] If Qualcomm/Lenovo agree to redistribute firmware:
  - Submit to linux-firmware.git via email to `linux-firmware@kernel.org`
  - Include WHENCE file entry with license information
  - This enables fully automated installation without firmware extraction

---

## Phase 9: Testing & Validation Matrix

### Functional Tests
| Test | Pass Criteria |
|------|--------------|
| Cold boot to desktop | GNOME/KDE loads, login works |
| NVMe performance | Sequential read > 3 GB/s (PCIe 4.0 x4) |
| WiFi 6E/7 connection | Connects to AP, stable throughput |
| Bluetooth audio | A2DP streaming works |
| Gigabit Ethernet | iperf3 > 900 Mbps |
| HDMI output | 4K@60 desktop rendering |
| DisplayPort output | 4K@60 desktop rendering |
| USB-C DP alt-mode | External display works |
| Multi-monitor | 2-3 displays simultaneously |
| Audio out | Headphone jack plays audio |
| Audio in | Microphone records audio |
| All USB ports | Storage and HID on each port |
| Suspend/resume | Completes cycle, all peripherals resume |
| Reboot | Clean reboot without hang |
| Thermal under load | No throttling below 90C ambient |
| GPU acceleration | glxgears/vkcube render correctly |

### Compatibility Tests
| Test | Target |
|------|--------|
| Ubuntu 25.10 arm64 ISO | Install and run from USB, then disk |
| Ubuntu 26.04 arm64 ISO | Install and run from USB, then disk |
| Fedora 42 arm64 | Install and run |
| Arch Linux ARM | Install and run |
| Kernel mainline HEAD | Build and boot |
| Kernel stable (latest LTS) | Build and boot |

---

## Phase 10: Community & Documentation

### 10.1 Documentation to Produce
- [ ] Wiki page for the Lenovo IdeaCentre Mini x on the Ubuntu community wiki or Arch wiki
- [ ] Installation guide with step-by-step instructions
- [ ] Known issues and workarounds list
- [ ] Hardware compatibility matrix

### 10.2 Community Engagement
- [ ] Update Launchpad bug #2136311 with progress and working patches
- [ ] Post on Ubuntu Discourse with boot instructions
- [ ] Engage with Linaro's Qualcomm Platform Services team
- [ ] Post on Fedora Discussion for Snapdragon X SIG
- [ ] Coordinate with Mostafa Saleh (misaleh) on his existing work
- [ ] Submit device to the dtbloader tracking issue

### 10.3 Coordinate with Lenovo
- [ ] Request firmware redistribution permission
- [ ] Request hardware documentation (schematics, GPIO maps) -- unlikely but worth asking
- [ ] Report UEFI firmware bugs if found
- [ ] Request LVFS (Linux Vendor Firmware Service) support for firmware updates

---

## Milestone Summary

| Milestone | Target | Description |
|-----------|--------|-------------|
| **M0** | Week 1-2 | Hardware acquired, Windows data captured, dev environment ready |
| **M1** | Week 3-4 | Full hardware audit complete, all components identified |
| **M2** | Week 5-8 | Device tree v1 complete, boots to desktop with display output |
| **M3** | Week 9-12 | All peripherals working (audio, WiFi, BT, all USB ports, Ethernet) |
| **M4** | Week 13-14 | DTBLoader integration, Ubuntu Concept ISO boots out-of-box |
| **M5** | Week 15-16 | Patches submitted to LKML for upstream review |
| **M6** | Week 17-24 | Upstream review cycles, patch revisions, merge |
| **M7** | Week 25+ | Included in Ubuntu/Fedora/Arch releases, firmware upstream |

---

## Key Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| GPU support missing from x1p42100.dtsi | No display output | Work with Linaro/Qualcomm to add GPU nodes to Purwa DTSI upstream |
| X1-26-100 (base Snapdragon X) differs from X1P-42-100 at SoC level | May need new base DTSI | Verify early in Phase 1; may need to create x1_26100.dtsi |
| Firmware not redistributable | Users must extract from Windows | Document extraction process clearly; lobby for upstream inclusion |
| Audio SoundWire driver immature | No sound | Track upstream development; contribute fixes if able |
| Bluetooth not working on any X1P device | No BT | This is a platform-wide issue being worked on by Linaro |
| Upstream review takes multiple cycles | Delay before official distro support | Use dtbloader and custom ISOs as interim solution |
| Watchdog timeout crashes | Unstable system | Identify and disable/configure the watchdog correctly in DTS |
| Display bridge chips unidentified | Can't configure HDMI/DP output | Physical hardware inspection or ACPI table analysis required |

---

## Repository Structure (This Repo)

This repo is the shared workspace between the Pi 5 and Lenovo Claude Code instances.

```
lenovo-mini-ubuntu/
  PLAN.md                              # This document
  CLAUDE.md                            # Instructions for Claude Code instances on both machines
  hardware/
    hardware-map.md                    # Definitive component-to-driver map (Pi produces from data)
    acpi-tables/                       # ACPI tables (extracted from Windows and Linux)
    dmi-data.txt                       # DMI/SMBIOS dump (Lenovo captures)
    pci-devices.txt                    # Windows PCI device IDs (Lenovo captures)
    pci-detailed.txt                   # Detailed PCI with hardware IDs (Lenovo captures)
    usb-topology.txt                   # Windows USB tree (Lenovo captures)
    usb-detailed.txt                   # Detailed USB with port mapping (Lenovo captures)
    network-adapters.txt               # Network adapter details (Lenovo captures)
    display-info.txt                   # Display/GPU info (Lenovo captures)
    audio-info.txt                     # Audio device info (Lenovo captures)
    firmware-info.txt                  # BIOS/firmware versions (Lenovo captures)
    partition-layout.txt               # Disk partition table (Lenovo captures)
    secureboot-info.txt                # Secure Boot state (Lenovo captures)
    pnp-devices.txt                    # Full PnP device list (Lenovo captures)
    acpi-devices.txt                   # ACPI device enumeration (Lenovo captures)
    msinfo32-report.txt                # Full msinfo32 system report (Lenovo captures)
    linux-audit/                       # Data captured from Linux boot (Lenovo runs, Pi analyzes)
      dmesg.txt
      cpuinfo.txt
      iomem.txt
      interrupts.txt
      lspci.txt
      lsusb-tree.txt
      lsusb-verbose.txt
      dt-nodes.txt
      regulators.txt
      thermal-zones.txt
      dmidecode.txt
  dts/
    x1p42100-lenovo-ideacentre-mini-x.dts  # Our device tree (Pi authors, Lenovo tests)
  kernel/
    defconfig                          # Kernel config (Pi maintains)
    patches/                           # Kernel patches not yet upstream (Pi authors)
  firmware/
    extract.sh                         # Firmware extraction script (runs on Lenovo Windows)
    firmware-manifest.txt              # File list with hashes (Lenovo captures, no blobs in git)
  dtbloader/
    lenovo_ideacentre_mini_x.c         # DTBLoader device definition
  scripts/
    hardware-audit.sh                  # Auto-capture script for Linux boot on Lenovo
    build-kernel.sh                    # Kernel build script for Pi 5
    make-bootable-usb.sh               # Create bootable USB from built kernel
  docs/
    install-guide.md                   # End-user installation instructions
    known-issues.md                    # Known issues and workarounds
  testing/
    test-matrix.md                     # Test results
    boot-logs/                         # Collected dmesg outputs per test run
```

### File Ownership

| Directory/File | Primary Author | Consumer |
|---------------|----------------|----------|
| `hardware/*.txt` | Lenovo (Windows) | Pi (analysis) |
| `hardware/linux-audit/` | Lenovo (Linux boot) | Pi (analysis) |
| `hardware/hardware-map.md` | Pi (synthesis) | Both |
| `dts/` | Pi (authoring) | Lenovo (testing) |
| `kernel/` | Pi (build/config) | Lenovo (testing) |
| `firmware/` | Lenovo (extraction) | Lenovo (Linux boot) |
| `scripts/` | Pi (authoring) | Both |
| `testing/` | Lenovo (execution) | Pi (analysis) |

---

## References

### Existing Work
- Mostafa Saleh's fork: https://github.com/misaleh/linux/tree/lenovo
- Launchpad bug: https://bugs.launchpad.net/ubuntu-concept/+bug/2136311
- DTBLoader: https://github.com/TravMurav/dtbloader

### Upstream Kernel
- Mainline kernel DTS: https://github.com/torvalds/linux/tree/master/arch/arm64/boot/dts/qcom
- Patch submission guide: https://docs.kernel.org/process/submitting-patches.html
- DT bindings guide: https://docs.kernel.org/devicetree/bindings/submitting-patches.html

### Community & Distribution
- Ubuntu Concept: https://discourse.ubuntu.com/t/ubuntu-concept-snapdragon-x-elite/48800
- Ubuntu FAQ for Snapdragon X: https://discourse.ubuntu.com/t/faq-ubuntu-25-04-25-10-on-snapdragon-x-elite/61016
- Fedora Snapdragon X SIG: https://discussion.fedoraproject.org/t/snapdragon-x-elite-fedora-42-system-bring-up-and-looking-for-collaborators-or-sigs/153631
- Linaro blog: https://www.linaro.org/blog/linux-on-snapdragon-x-elite/

### Hardware
- Lenovo product page: https://www.lenovo.com/gb/en/p/desktops/ideacentre/500-series/lenovo-ideacentre-mini-x-gen-10-snapdragon/len102d0040
- Lenovo PSREF spec sheet: https://psref.lenovo.com/syspool/Sys/PDF/IdeaCentre/IdeaCentre_Mini_01Q8X10/IdeaCentre_Mini_01Q8X10_Spec.pdf
- Qualcomm upstream blog: https://www.qualcomm.com/developer/blog/2024/05/upstreaming-linux-kernel-support-for-the-snapdragon-x-elite

### Mailing Lists
- linux-arm-msm: https://lore.kernel.org/linux-arm-msm/
- devicetree: https://lore.kernel.org/devicetree/
- linux-firmware: linux-firmware@kernel.org
