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
  - `clk_ignore_unused pd_ignore_unused`: confirmed working (dmesg: "Not disabling unused clocks")
  - Without DTB (ACPI-only): no display at all (no Tux logo)
  - With DTB + best cmdline: Tux logo + brief text, then black -- display still lost
  - **Root cause**: DRM_MSM=y (built-in) probes and takes over from efifb; clock/power protection helps but doesn't fully fix it
  - **NEXT**: Get SSH over Ethernet for interactive access (Ethernet confirmed working)
- [x] First successful Linux boot via blind capture (2026-02-16, lenovo-win)
  - Kernel boots fully with DTB + `clk_ignore_unused pd_ignore_unused`
  - Blind boot initramfs writes 19 log files to USB FAT32 partition
  - All logs captured and saved to `testing/boot-logs/2026-02-16-first-boot/`
- [ ] Commit all captured data to `testing/boot-logs/2026-02-16-first-boot/`

### 1.3 Analysis
- [x] Cross-reference Windows PnP device IDs with Linux PCI scan (2026-02-16, lenovo-win)
  - PCI devices confirmed in Linux: WiFi (17cb:1107), Ethernet (10ec:8168), NVMe (144d:a80d), 3x PCIe root ports (17cb:0111)
- [x] Identify the Ethernet controller: **Realtek RTL8168h** (VEN_10EC DEV_8168), driver: `r8169` -- **WORKING** (2026-02-15/16)
  - MAC: 18:3d:2d:ce:9f:ac, link detected, interface `eth0`
- [x] Identify USB hub chip: **Genesys Logic GL3510** (VID 05E3, PID 0610/0625) (2026-02-15, lenovo-win)
  - USB2.1 Hub (0610) + USB3.2 Hub (0625) confirmed in Linux boot logs
- [x] Identify Bluetooth transport: **UART H4** (ACPI QCOM0C6B) (2026-02-15, lenovo-win)
- [x] WiFi chip confirmed: **Qualcomm FastConnect 7800** (17cb:1107), no driver bound (needs `ath12k` + firmware) (2026-02-16, lenovo-win)
- [ ] Identify display bridge chips (HDMI/DP) -- DTB has 2 DisplayPort controllers (ae90000, aea0000) + 3 retimer regulators
- [x] Identify retimer chips (2026-02-18, pi) -- ps8830 (Parade DP retimer), ptn3222 (NXP USB-C redriver)
- [ ] Identify VID_17EF PID_6044 Lenovo USB device
- [ ] Compare ACPI tables against DT nodes to find missing hardware descriptions
- [ ] Produce `hardware/hardware-map.md` -- the definitive component-to-driver mapping

### Key Findings from First Linux Boot (2026-02-16)
- **Kernel:** 6.19.0-rc4-g740f9e80d577 (Mostafa's lenovo branch)
- **DT compatible:** `lenovo,ideacentre-x-gen10 qcom,x1p42100`
- **CPU:** 8 Oryon cores -- CPUs 0-3 variant 0x2 (performance), CPUs 4-7 variant 0x1 (efficiency)
- **RAM:** 32GB (32071124K/33116864K available)
- **PCI devices (6):**
  - 3x Qualcomm PCIe root ports (17cb:0111) -- segments 4, 5, 6
  - WiFi: Qualcomm 17cb:1107 -- no driver (ath12k needs firmware)
  - Ethernet: Realtek 10ec:8168 -- r8169 driver, **working**
  - NVMe: Samsung 144d:a80d -- nvme driver, **working** (all 4 Windows partitions visible)
- **USB devices:** 4x xHCI controllers, GL3510 hubs, keyboard (1a2c:2124), mouse (1c4f:0034), SanDisk boot USB
- **Display:** efifb at e4800000-e4fe8fff, 2 DisplayPort controllers in DTB, 3 retimer regulators (all enabled)
- **Regulators:** 55 total, key ones enabled: VREG_EDP_3P3, VREG_NVME_3P3, VREG_RTMR0/1/2
- **Missing firmware:** adsp.mbn, cdsp.mbn, wpss.mbn, regulatory.db (expected -- remoteprocs not started)
- **Non-critical errors:** PMIC glink connector link error, mouse reconnect cycling, modem remoteproc crash (no firmware)

---

## Phase 2: Interactive Linux Access (Next Steps)

The first blind boot proved the kernel works. The immediate priority is getting interactive access without relying on display output (which is still broken).

### 2.1 SSH over Ethernet
Ethernet (r8169) is confirmed working. Next boot should bring up the network and start an SSH server.
- [x] Build initramfs with dropbear (lightweight SSH server) (2026-02-16, lenovo-win)
- [x] Configure initramfs to: bring up eth0 via DHCP, start dropbear/sshd (2026-02-16, lenovo-win)
  - v1 initramfs had two bugs discovered on 2026-02-17:
    1. Missing `/usr/share/udhcpc/default.script` -- DHCP lease obtained but IP never configured
    2. `ld-linux-aarch64.so.1` was self-referential symlink -- dropbear couldn't start
  - v2 initramfs fixed udhcpc script but used wrong variable (`$mask` vs `$subnet`)
  - v3 initramfs (2026-02-17, pi): fixed both -- real ld-linux binary + ifconfig-based udhcpc script
- [ ] Boot Lenovo, SSH in from another machine on the LAN
- [ ] Verify interactive shell access works

#### Boot Attempts Log (2026-02-17, pi)
- **Boot 3 (v1 initramfs):** DHCP packets sent (router saw MAC), but udhcpc had no default.script so IP never configured. System stayed alive (watchdog NOT the problem). Logs: `testing/boot-logs/2026-02-17-watchdog-kill/`
- **Boot 4 (v2 initramfs):** Carrier detected after 4s, DHCP lease obtained (192.168.1.15), but udhcpc script used `$mask` (undefined) instead of `$subnet` so `ip addr add` failed silently. Dropbear failed with "Too many levels of symbolic links" (ld-linux self-referential symlink). System alive at 29.7s -- confirms watchdog is NOT killing the system. Logs: `testing/boot-logs/2026-02-17-dhcp-works-ssh-broken/`
- **Boot 5 (v3 initramfs, 2026-02-18):** Same errors persisted despite fixes being verified in cpio archive. Possible initramfs loading mismatch (kernel reported 2752K freed vs 2844K file). Logs: `testing/boot-logs/2026-02-18-boot5-dhcp-ok-ip-missing/`
- **Boot 6 (v4 initramfs, 2026-02-18):** SUCCESS! Build marker v4-pi-20260218-204435. DHCP works, IP configured (192.168.1.15), ping works. Telnet (port 23) provides interactive shell. SSH (dropbear) connects but rejects login: `/root` permissions wrong + password not set correctly. Full interactive hardware exploration completed via telnet. Logs + analysis: `testing/boot-logs/2026-02-18-boot6-telnet-interactive/`
- [x] Interactive shell access via telnet (2026-02-18, pi)
- [ ] Fix SSH: correct /root permissions (0700 root:root) + set root password properly

#### Boot 6 Key Findings (2026-02-18, pi -- first interactive session)
- **DT model:** "Lenovo IdeaCentre X Gen 10 Snapdragon"
- **DT compatible:** `lenovo,ideacentre-x-gen10`, `qcom,x1p42100`
- **DRM/Display:** Completely disabled (`drm.modeset=0` + `nomodeset`). efifb works (1920x1080x32). Display-subsystem, DPU, 2x DP controllers all in platform devices but not probed.
- **I2C retimers:** ps8830 (Parade DP retimer), ptn3222 (NXP USB-C redriver)
- **Retimer regulators:** Only RTMR0 powered; RTMR1, RTMR2, EDP_3P3 all disabled
- **Power domains:** mdss_gdsc OFF, gpu_cc_* OFF, mmcx ON (display clocks available)
- **Remoteproc firmware path:** `qcom/x1e80100/` (NOT x1p42100) -- adsp.mbn, cdsp.mbn both ENOENT
- **PMIC glink:** Failed to link with connector@0 supplier 2-0008 (Type-C mux)
- **Clock sync_state:** gcc + gpucc pending due to GMU (3d6a000.gmu)
- **LPASS pinctrl:** deferred probe -- "Failed to get clk 'core'" (audio broken)
- **USB mouse bug:** SIGMACHIP 1c4f:0034 reconnects every ~2.5s, flooding dmesg
- **NVMe:** Samsung MZVL8512HDLU-00BLL, FW 9L2QKXD7, 4 partitions (EFI/Reserved/Windows/Recovery)
- **System stable:** Stayed alive >30 minutes, thermals 21-23C SoC, 37C PMICs

#### Boot 7 Key Findings (2026-02-18, pi -- DRM enabled, display test)
- **Cmdline:** `clk_ignore_unused pd_ignore_unused console=tty0 earlycon earlyprintk loglevel=8 keep_bootcon drm.debug=0x1ff log_buf_len=8M` (no nomodeset, no drm.modeset=0)
- **DRM probed:** DPU mapped address space, DP1 (eDP) did PHY init then exited, DP0 (USB-C) had no DRM activity
- **DRM card NOT created:** Component aggregate `ae01000.display-controller` never bound
- **Root cause:** DPU expects 3 components via port graph, only DP0 registered. DP1 (aea0000) probed as platform device but never called component_add() -- likely because eDP panel probe failed (no panel on desktop)
- **DPU port graph:** port@0→DP0 (ae90000), port@4→DP2 (ae98000, disabled), port@5→DP1 (aea0000), port@6→DP3 (ae9a000, disabled)
- **efifb survives:** DRM didn't take over, screen stays on EFI framebuffer
- **System stable:** Network + telnet still work with DRM enabled
- **Initramfs v5:** fakeroot-built (root:root), new password hash. SSH still rejects -- needs more investigation
- **HDMI bridge:** No bridge chip in DT. Codex suggests Realtek RTD2171 based on ThinkBook 16 patches. Needs identification from Windows driver data
- Logs: `testing/boot-logs/2026-02-18-boot7-drm-enabled/`

#### Boot 8 Key Findings (2026-02-26, pi -- DRM enabled, DP1 disabled in DTB)
- **DTB fix:** DP1/mdss_dp3 (aea0000, eDP) set to `status = "disabled"` via dtc decompile/edit/recompile on Pi 5
- **Initramfs v6:** SSH key auth (ed25519 authorized_keys for Pi)
- **DRM card0 CREATED!** Component aggregate `ae01000.display-controller` bound successfully
- `bound ae90000.displayport-controller (ops msm_dp_display_comp_ops)`
- `bound 3d00000.gpu (ops a3xx_ops)` -- GPU Adreno 67.3.12.0 bound
- **DRM card0** with DP-1 connector, Writeback-1 connector, renderD128
- **SSH key auth works** -- `ssh root@192.168.1.15` connects immediately
- **DP-1 connector: disconnected** -- `link_ready = false`, no HPD signal
- Root cause: `CONFIG_TYPEC_DP_ALTMODE=m` and `CONFIG_TYPEC_QCOM_PMIC=m` -- modules never loaded
- Logs: `testing/boot-logs/2026-02-26-boot8-drm-dp1-disabled/`

#### Boot 9 Key Findings (2026-02-26, pi -- typec drivers built-in)
- **Kernel rebuilt on Pi 5** with `CONFIG_TYPEC_DP_ALTMODE=y` and `CONFIG_TYPEC_QCOM_PMIC=y`
- All auxiliary bus drivers bound: pmic_glink_altmode, ucsi_glink, aux_hpd_bridge, aux_bridge (x2)
- **DP-1 still disconnected** -- `link_ready = false`
- `Failed to create device link (0x180)` is **red herring** -- flags are `DL_FLAG_SYNC_STATE_ONLY | DL_FLAG_INFERRED`, non-fatal
- **Real cause:** ADSP firmware missing → UCSI can't communicate → no typec ports → no DP alt mode → no HPD
- `remoteproc0 adsp: Direct firmware load for qcom/x1e80100/adsp.mbn failed with error -2`

#### Boot 10 Key Findings (2026-02-26, pi -- NTFS3 support, firmware extraction)
- **Kernel rebuilt with CONFIG_NTFS3_FS=y** for Windows partition access
- **BitLocker disabled** from Windows, drive decrypted
- **Mounted Windows NTFS partition** (`/dev/nvme0n1p3`) successfully
- **Extracted all 10 firmware files** from `Windows/System32/DriverStore/FileRepository/`:
  - ADSP: qcadsp8380.mbn, adsp_dtbs.elf, adspr.jsn, adsps.jsn, adspua.jsn, battmgr.jsn
  - CDSP: qccdsp8380.mbn, cdsp_dtbs.elf, cdspr.jsn
  - GPU: qcdxkmsuc8380.mbn
- **ADSP and CDSP started manually** via `echo start > /sys/class/remoteproc/remoteprocN/state`
  - `remote processor adsp is now up` -- ADSP running!
  - `remote processor cdsp is now up` -- CDSP running!
  - PMIC_RTR_ADSP_APPS rpmsg channel appeared and bound to qcom_pmic_glink_rpmsg
  - Battery manager power supplies appeared (qcom-battmgr-*)
  - But UCSI still didn't register typec ports (ADSP started too late, after PMIC glink probe)
- **Firmware saved to USB** at `/firmware/qcom/x1e80100/` and `/firmware/qcom/x1p42100/`
- **Initramfs v7 built** with firmware baked in (16.9MB) -- firmware will be available at boot
- **Codex analysis** (2 sessions):
  - `0x180` device link error is noisy/non-fatal fw_devlink behavior
  - HDMI on this desktop may NOT go through USB-C alt mode -- could be a direct DP path through mdss_dp3 (aea0000) to an external HDMI bridge (RTD2171)
  - Recommended: re-enable mdss_dp3, remove eDP panel node, add HDMI bridge+connector graph

#### Boot 11 Key Findings (2026-02-26, pi -- firmware in initramfs, QRTR_SMD investigation)
- **Kernel rebuilt with CONFIG_QRTR_SMD=y** (was =m)
- **Initramfs v7 with firmware** -- ADSP and CDSP both start automatically at boot (~4 seconds)
  - `remoteproc0 adsp: remote processor adsp is now up`
  - `remoteproc1 cdsp: remote processor cdsp is now up`
- **PMIC_RTR_ADSP_APPS** rpmsg channel established at boot
- **Battery manager** power supplies registered (qcom-battmgr-*)
- **DP-1 still disconnected** -- `ls /sys/class/typec/` is empty, UCSI never registered typec ports
- **Root cause chain identified:**
  1. `CONFIG_QRTR_SMD=m` -- QRTR SMD transport not loaded → QRTR can't talk to ADSP
  2. `CONFIG_QCOM_PD_MAPPER=m` -- in-kernel pd-mapper not loaded → PDR service locator has no provider
  3. Without pd-mapper, PDR can't discover `msm/adsp/charger_pd` service → `pd_running` stays false → UCSI never registers
- **Codex analysis (3rd session):** Confirmed both QRTR_SMD and PD_MAPPER must be built-in. Provided full recommended config list.
- **Kernel rebuilt with both fixes:** `CONFIG_QRTR_SMD=y` + `CONFIG_QCOM_PD_MAPPER=y`
- **Full PDR chain now all built-in:**
  - QRTR=y, QRTR_SMD=y, QCOM_QMI_HELPERS=y, QCOM_PDR_HELPERS=y, QCOM_PDR_MSG=y, QCOM_PD_MAPPER=y
  - QCOM_PMIC_GLINK=y, UCSI_PMIC_GLINK=y, TYPEC_DP_ALTMODE=y, TYPEC_QCOM_PMIC=y
- New kernel transferred to USB, checksums verified, ready for Boot 12

### 2.2 Full Rootfs (debootstrap)
A busybox initramfs is too limited for real debugging. Need a proper Ubuntu rootfs.
- [ ] Create arm64 Ubuntu rootfs via debootstrap in WSL2
- [ ] Include: openssh-server, NetworkManager, firmware-linux, pciutils, usbutils
- [ ] Package as initramfs or place on NFS/USB partition
- [ ] Boot with full rootfs, verify SSH + package management

### 2.3 Display Enablement
Boot 8 confirmed: DRM card0 created when mdss_dp3 (aea0000, eDP) disabled.
Boot 9-10: DP-1 connector exists but "disconnected" -- HPD not firing.

**Two parallel display paths identified:**
1. **USB-C DP alt mode (DP0/ae90000):** Goes through PMIC glink → PS8830 retimer → USB3-DP PHY. Requires ADSP firmware for UCSI/typec. Firmware extracted and baked into initramfs v7.
2. **Direct HDMI (mdss_dp3/aea0000, suspected):** May connect to external DP-to-HDMI bridge chip (likely Realtek RTD2171) NOT described in DT. Currently disabled -- needs re-enabling with correct bridge node instead of eDP panel.

**Completed:**
- [x] Disable mdss_dp3 (aea0000) eDP panel -- proved DRM card creation works (2026-02-26, pi)
- [x] Rebuild kernel with typec drivers built-in (2026-02-26, pi)
- [x] Extract Qualcomm firmware from Windows partition (2026-02-26, pi)
- [x] Bake firmware into initramfs v7 (2026-02-26, pi)
- [x] Kernel built on Pi 5 with ccache (`make -j4 CC="ccache gcc"`) -- native ARM64, no cross-compile
- [x] ADSP/CDSP start automatically at boot with firmware in initramfs (2026-02-26, pi)
- [x] Iteratively fixed all module→builtin configs for PDR/UCSI chain (2026-02-26, pi):
  - TYPEC_DP_ALTMODE=y, TYPEC_QCOM_PMIC=y (Boot 9)
  - QRTR_SMD=y (Boot 11)
  - QCOM_PD_MAPPER=y (Boot 12 prep)

**Next steps:**
- [ ] Boot 12: Verify UCSI registers typec ports now that full PDR chain is built-in
- [ ] Test USB-C display output (plug monitor into rear USB-C port)
- [ ] Identify HDMI bridge chip from Windows driver INFs or I2C enumeration
- [ ] Re-enable mdss_dp3 with HDMI bridge node instead of eDP panel
- [ ] Add bridge node (likely `simple-bridge` + `realtek,rtd2171`) to DTS
- [ ] Test HDMI output

### 2.4 WiFi Enablement
- [ ] Copy ath12k firmware files to rootfs (`/lib/firmware/ath12k/`)
- [ ] Extract firmware from Windows driver package or linux-firmware repo
- [ ] Test WiFi association

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
- First successful Linux boot (2026-02-16): blind capture to USB, 19 log files in `testing/boot-logs/2026-02-16-first-boot/`
  - Kernel fully functional, all major subsystems probed
  - Ethernet, NVMe, USB all working with drivers
  - WiFi detected but needs firmware; display needs DRM_MSM debugging
  - Next priority: SSH over Ethernet for interactive access
- SSH boot debugging (2026-02-17, pi):
  - SBSA GWDT watchdog (10s timeout) was initial suspect for system death -- **DISPROVEN**
  - `nowatchdog` kernel param only affects software lockup detector, not hardware watchdog
  - Codex CLI review confirmed: kernel watchdog core auto-pings via WDOG_HW_RUNNING
  - System stays alive well past 29s (init-trace.txt proves it)
  - Real bugs: (1) missing udhcpc default.script, (2) ld-linux self-referential symlink
  - Initramfs patched on Pi: extracted cpio.gz, fixed both bugs, repacked
  - `build-initramfs.sh` in repo still has these bugs -- needs updating on WSL2
- Boot 6 interactive session (2026-02-18, pi):
  - Telnet access works (busybox telnetd, statically linked, no ld-linux needed)
  - Dropbear SSH is running but rejects login: wrong /root perms + password issue
  - Display architecture confirmed: MDSS -> DPU -> 2x DP controllers, DP0 via USB3/DP PHY, DP1 has eDP panel child
  - Only retimer 0 is powered -- retimers 1 and 2 disabled (explains partial display)
  - PMIC glink can't link to Type-C mux (2-0008) -- affects USB-C DP alt mode
  - Firmware paths use `qcom/x1e80100/` not `qcom/x1p42100/` -- DTSi inherits from x1e80100
  - Next steps: (1) fix SSH, (2) try boot with DRM enabled, (3) extract firmware from Windows
