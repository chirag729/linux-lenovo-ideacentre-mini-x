# Progress Tracker

This file tracks granular progress. See `PLAN.md` for the full plan and context.

Always `git pull` before reading, `git push` after updating.

---

## Phase 0: Prerequisites & Environment Setup

### 0.1 Hardware & Accounts
- [x] Obtain Lenovo IdeaCentre Mini x Gen 10 (2026-02-15, user)
- [x] Create GitHub repo: `chirag729/linux-lenovo-ideacentre-mini-x` (2026-02-15)
- [x] Push initial repo with PLAN.md, CLAUDE.md, scripts (2026-02-15)
- [x] Confirm Windows 11 on ARM is installed and fully updated on Lenovo (2026-02-15, lenovo-win)

### 0.2 Set Up Lenovo Windows Instance
- [x] Install git for Windows ARM64 on Lenovo (2026-02-15, lenovo-win)
- [x] Install Claude Code on Lenovo Windows (2026-02-15, lenovo-win)
- [x] Set up GitHub access (SSH key or HTTPS) (2026-02-15, lenovo-win)
- [x] Clone the repo on Lenovo Windows (2026-02-15, lenovo-win)
- [x] Verify Claude Code can run PowerShell commands on Lenovo (2026-02-15, lenovo-win)
- [x] Test git push from Lenovo Windows (2026-02-15, lenovo-win)

### 0.3 Set Up Lenovo WSL2 Instance
- [x] Install WSL2 on Lenovo (2026-02-16, lenovo-win)
- [x] Reboot and set WSL2 username and password (2026-02-16, lenovo-win)
  - Ubuntu 24.04.4 LTS, aarch64, 15GB RAM visible to WSL2
- [x] Install build dependencies in WSL2 (2026-02-16, lenovo-win)
  - gcc 13.3.0, ccache, dtc, flex, bison, etc.
- [x] Install dtschema and yamllint (2026-02-16, lenovo-win)
- [x] Configure ccache in WSL2: 10GB max (2026-02-16, lenovo-win)
- [ ] Generate SSH key in WSL2 for GitHub
- [ ] Add WSL2 SSH public key to GitHub
- [x] Clone project repo in WSL2: `~/Projects/lenovo-mini-ubuntu` (2026-02-16, lenovo-win)
- [x] Clone mainline kernel in WSL2: `~/kernel/linux` (shallow, 2026-02-16, lenovo-win)
- [x] Clone Mostafa's fork in WSL2: `~/kernel/misaleh-linux` (lenovo branch, 2026-02-16, lenovo-win)
- [x] Clone dtbloader in WSL2: `~/kernel/dtbloader` (2026-02-16, lenovo-win)
- [x] Verify WSL2 can access Windows filesystem via `/mnt/c/` (2026-02-16, lenovo-win)
- [x] Verify build works in WSL2: `make defconfig && make -j7 Image` -- SUCCESS (2026-02-16, lenovo-win)
- [ ] Test git push from WSL2

### 0.4 Set Up Netbox
- [ ] Choose a machine to use as netbox (any always-on Linux box on the LAN)
- [ ] Install packages: `sudo apt install tftpd-hpa nfs-kernel-server screen`
- [ ] Configure TFTP server:
  ```bash
  sudo mkdir -p /srv/tftp
  # Edit /etc/default/tftpd-hpa: TFTP_DIRECTORY="/srv/tftp"
  sudo systemctl enable --now tftpd-hpa
  ```
- [ ] Verify TFTP is running: `sudo systemctl status tftpd-hpa`
- [ ] Configure NFS server:
  ```bash
  sudo mkdir -p /srv/nfs/lenovo-rootfs
  # Add to /etc/exports: /srv/nfs/lenovo-rootfs *(rw,no_root_squash,no_subtree_check)
  sudo exportfs -ra
  sudo systemctl enable --now nfs-kernel-server
  ```
- [ ] Verify NFS is running: `sudo systemctl status nfs-kernel-server`
- [ ] Verify netconsole listener works: `nc -u -l -p 6666`

### 0.5 Verify Cross-Machine Communication
- [ ] From netbox, confirm Lenovo is reachable: `ping <lenovo-ip>`
- [ ] From Lenovo WSL2, confirm netbox is reachable: `ping <NETBOX_IP>`
- [ ] From Lenovo WSL2, confirm rsync to netbox works:
  ```bash
  rsync -av --dry-run ~/kernel/linux/Makefile user@netbox:/tmp/
  ```

---

## Phase 0.6: Windows Hardware Audit

- [x] Run `scripts/windows-hardware-audit.ps1` on Lenovo (2026-02-15, lenovo-win)
- [x] Re-run as Administrator for SecureBoot data (2026-02-15, lenovo-win)
- [x] Review output in `hardware/` directory -- 27 files captured (2026-02-15, lenovo-win)
- [ ] Commit and push results

### Key Findings from Windows Audit (2026-02-15)
- **CPU:** Snapdragon X X1-26-100 (Purwa die), 8-core Oryon @ 2956 MHz, 24MB L2
- **GPU:** Adreno X1-45 (ACPI QCOM0D17, driver INF confirms Purwa die)
- **Ethernet:** Realtek RTL8168 (VEN_10EC DEV_8168) -- Linux driver: `r8169` (mature, should just work)
- **WiFi:** Qualcomm FastConnect 7800 (VEN_17CB DEV_1107), PCIe seg 4 x2 -- Linux driver: `ath12k`
- **Bluetooth:** FastConnect 7800 Dual BT, UART H4 transport (ACPI QCOM0C6B)
- **NVMe:** Samsung MZVL8512HDLU-00BLL 512GB (only 1 drive detected, second M.2 slot likely empty)
- **USB Controllers:** 1x xHCI (QCOM0D08), 1x DWC3 (QCOM0C8B), 1x USB4 (QCOM0C6D)
- **USB Hub:** Genesys Logic GL3510 (VID 05E3, PID 0610/0625) -- internal hub for USB-A ports
- **Audio:** Qualcomm Aqstic (QCOM0CE6, QCOM0C29, QCOM0CC1) + external display audio
- **Secure Boot:** Enabled
- **BIOS:** O6NKT3BA (2025-02-05), EC v0.22, SMBIOS 3.6
- **PCIe:** 3 root complexes (segments 4=WiFi, 5=Ethernet, 6=NVMe)
- **Lenovo USB device:** VID_17EF PID_6044 present (likely internal, needs identification)

---

## Phase 1: Hardware Audit & Identification

### 1.1 Windows-Side Audit
- [x] Windows-side audit complete via `windows-hardware-audit.ps1` (2026-02-15, lenovo-win)
- [ ] Extract ACPI tables with `acpidump.exe` → `hardware/acpi-tables/`
- [x] Run `msinfo32 /report hardware/msinfo32-report.txt` (2026-02-16, lenovo-win)

### 1.2 Linux-Side Audit (after first Linux boot)
- [x] Build Mostafa's kernel from `lenovo` branch on WSL2 (2026-02-16, lenovo-win)
  - Kernel: 6.19.0-rc4-g740f9e80d577 from `lenovo` branch
  - Image: ~/kernel/misaleh-linux/arch/arm64/boot/Image (53MB)
  - DTB: ~/kernel/misaleh-linux/arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-x-gen10.dtb (196KB)
  - Built with `qcom_defconfig` + `make -j7`
- [x] Create bootable USB stick with GRUB-EFI arm64 (2026-02-16, lenovo-win)
  - SanDisk 3.2Gen1 (~28.6GB), GPT, 512MB FAT32 EFI System Partition
  - GRUB EFI binary built with `grub-mkimage` including `fdt` module for devicetree loading
  - Minimal busybox initramfs (985KB) with hardware audit init script
  - Files: /EFI/BOOT/BOOTAA64.EFI, /EFI/BOOT/grub.cfg, /Image, /dtb/*.dtb, /initramfs.cpio.gz
- [x] First USB boot attempt (2026-02-16, lenovo-win)
  - GRUB menu displayed successfully on screen
  - First attempt: `fdt` command not found -- fixed: command name is `devicetree` (module is `fdt`)
  - Second attempt: devicetree loaded, kernel started (Tux logo visible), screen went black
  - Screen goes black because DRM_MSM driver (built-in) takes over from efifb and fails
- [x] QEMU ARM64 testing setup (2026-02-16, lenovo-win)
  - Installed qemu-system-arm in WSL2
  - Tested kernel+initramfs in QEMU (`-machine virt -cpu cortex-a76`)
  - Full boot confirmed: kernel boots, initramfs works, drops to busybox shell
  - Script: scripts/run-qemu.sh
- [ ] Fix display output on real hardware
  - `nomodeset` alone: still goes black (DRM_MSM is built-in =y, probes and kills efifb)
  - `nomodeset + video=efifb:on + drm.modeset=0 + keep_bootcon`: Tux logo + brief text visible
  - **NEXT**: Add `clk_ignore_unused pd_ignore_unused` to prevent clock/power domain shutdown
  - Without DTB (ACPI-only): no display at all (no Tux logo)
  - With DTB: display works initially but dies when unused clocks/power domains are disabled
- [ ] Boot Lenovo into Linux with console output visible
- [ ] Capture dmesg, lspci, lsusb, /proc/iomem, etc.
- [ ] Commit all captured data to `hardware/linux-audit/`

### 1.3 Analysis
- [ ] Cross-reference Windows PnP device IDs with Linux `lspci` output
- [x] Identify the Ethernet controller: **Realtek RTL8168** (VEN_10EC DEV_8168) (2026-02-15, lenovo-win)
- [x] Identify USB hub chip: **Genesys Logic GL3510** (VID 05E3) (2026-02-15, lenovo-win)
- [x] Identify Bluetooth transport: **UART H4** (ACPI QCOM0C6B) (2026-02-15, lenovo-win)
- [ ] Identify display bridge chips (HDMI/DP) -- needs ACPI table analysis or Linux boot
- [ ] Identify retimer chips -- needs I2C bus probing from Linux
- [ ] Identify VID_17EF PID_6044 Lenovo USB device
- [ ] Compare ACPI tables against DT nodes to find missing hardware descriptions
- [ ] Produce `hardware/hardware-map.md` -- the definitive component-to-driver mapping

---

## Blocked / Notes

Record any blockers, surprises, or decisions here:

- SecureBoot is enabled -- disabled for test booting, BitLocker suspended (`Suspend-BitLocker -MountPoint "C:" -RebootCount 0`)
- Only 1 NVMe drive detected (Samsung 512GB) -- second M.2 slot appears empty
- SUBSYS values in audio/GPU ACPI IDs contain `CRD08380` -- this is the CRD (Customer Reference Design) subsystem ID, confirming the board is closely related to the Qualcomm reference design
- Git Bash on Windows strips `$` variables from single-quoted strings passed to `wsl -d Ubuntu -- bash -c`. Workaround: write scripts to files and execute with `MSYS_NO_PATHCONV=1 wsl -d Ubuntu -- bash /mnt/c/path/to/script.sh`
- Windows line endings (`\r\n`) break scripts run in WSL2. Fix with `sed -i 's/\r$//' script.sh` before running
- EFI System Partition (ESP) requires Administrator access from Windows for both read and write
- Display debugging findings (2026-02-16):
  - CONFIG_DRM_MSM=y (built-in, not module) -- takes over from efifb even with nomodeset
  - CONFIG_FB_EFI=y, CONFIG_FRAMEBUFFER_CONSOLE=y -- efifb works initially (Tux logo visible)
  - Without DTB: no display (ACPI-only boot has no framebuffer info)
  - With DTB + nomodeset: brief display then black -- clocks/power domains being disabled
  - Best cmdline so far: `nomodeset video=efifb:on drm.modeset=0 clk_ignore_unused pd_ignore_unused console=tty0 earlycon earlyprintk loglevel=8 keep_bootcon`
