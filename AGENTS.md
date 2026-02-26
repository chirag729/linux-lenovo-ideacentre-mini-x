# Claude Code Project Instructions

## Project Overview

This project aims to get Linux (primarily Ubuntu) running on the Lenovo IdeaCentre Mini x Gen 10 with Snapdragon X X1-26-100 processor, and to upstream all work to the mainline Linux kernel so it ships in official distributions.

See `PLAN.md` for the full plan.

## Machine Setup

### Pi 5 (192.168.1.14) -- build host + netbox
- **Primary build host.** User prefers building here over WSL2 -- "happy to wait longer."
- **Build command:** `cd ~/kernel/misaleh-linux && make -j3 Image` (4 cores, 16GB RAM, NVMe, ccache)
- **Kernel source:** `~/kernel/misaleh-linux` (Mostafa's fork, 6.19-rc4 base)
- **Defconfig:** `~/Projects/lenovo-mini-ubuntu/kernel/defconfig`
- **Native ARM64** -- no cross-compile needed
- Can do quick DTB edits with `dtc` (decompile/edit/recompile)
- **Services:** TFTP at `/srv/tftp`, NFS root at `/srv/nfs/lenovo-rootfs`, netconsole listener
- **Secondary AI reviewers:** `codex` (OpenAI Codex CLI) installed. Use for second opinions on tricky debugging. Run with `codex exec "prompt"`.
- **Sudo requires password** -- cannot run privileged commands without user intervention.

### Lenovo IdeaCentre Mini x Gen 10 (target device)
- **IP:** 192.168.1.15 (when booted into Linux)
- **SSH:** `ssh root@192.168.1.15` (key auth, ed25519)
- **USB boot drive** mounted at `/mnt/usb` (FAT32) -- contains Image, dtb/, initramfs.cpio.gz
- **File transfer to USB:** `cat file | ssh root@192.168.1.15 'cat > /mnt/usb/file'` (no scp in initramfs)
- **Windows partition:** BitLocker disabled, NTFS mountable from Linux
- **UEFI:** GRUB boot menu with multiple options in `/mnt/usb/EFI/BOOT/grub.cfg`

## Git Workflow

- **NEVER run `git commit` or `git push` yourself.** Instead, provide the user with a one-line commit message and let them commit and push manually.
- Commit messages should be prefixed: `[lenovo-win]` or `[lenovo-wsl]`
- Hardware data goes in `hardware/`
- Never commit proprietary firmware blobs -- only manifests/hashes
- Boot logs go in `testing/boot-logs/` with date prefixes (e.g., `2026-02-15-dmesg.txt`)

## Key Commands

### Building the kernel (Pi 5)
```bash
cd ~/kernel/misaleh-linux
make -j3 Image          # full kernel, ~15-20 min with ccache
make -j3 Image dtbs     # kernel + device trees
make drivers/gpu/drm/msm/dp/dp_ctrl.o  # compile single file to check for errors
```

### Building just the device tree (Pi 5, fast iteration)
```bash
cd ~/kernel/misaleh-linux
make dtbs  # Rebuilds only changed DTS files, takes seconds
```

### Quick DTB edit without full rebuild
```bash
dtc -I dtb -O dts -o /tmp/board.dts /path/to/board.dtb   # decompile
# edit /tmp/board.dts
dtc -I dts -O dtb -o /tmp/board.dtb /tmp/board.dts        # recompile
```

### Deploying kernel to Lenovo USB (while Lenovo is running Linux)
```bash
# Copy kernel Image:
cat ~/kernel/misaleh-linux/arch/arm64/boot/Image | ssh root@192.168.1.15 'cat > /mnt/usb/Image'
# Copy DTB:
cat ~/kernel/misaleh-linux/arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-x-gen10.dtb | \
  ssh root@192.168.1.15 'cat > /mnt/usb/dtb/x1p42100-lenovo-ideacentre-x-gen10.dtb'
# Always sync after:
ssh root@192.168.1.15 'sync'
```

### Capturing boot logs from Lenovo
```bash
ssh root@192.168.1.15 'dmesg' > testing/boot-logs/$(date +%Y%m%d)-bootN-description/dmesg-full.txt
```

### Listening for netconsole on Pi 5
```bash
nc -u -l -p 6666 | tee testing/boot-logs/$(date +%Y%m%d-%H%M).txt
```

## Debug Access (When Display Doesn't Work)

Display output is initially broken. Use these methods:

1. **netconsole** -- kernel console over Ethernet to netbox (add to cmdline: `netconsole=@/eth0,6666@<NETBOX_IP>/`)
2. **SSH over Ethernet** -- interactive shell once rootfs is up
3. **Blind boot + capture script** -- `scripts/hardware-audit.sh` writes to partition

## Progress Tracking

Progress is tracked in `PROGRESS.md` at the repo root. This file contains granular step-by-step checklists for every task, including setup, configuration, and verification steps.

### Rules for Progress Tracking
- **Every instance** must update `PROGRESS.md` when completing a step
- Mark steps `[x]` only when verified working, not just attempted
- Add the date and instance tag when completing a step: `[x] (2026-02-15, lenovo-wsl)`
- If a step fails or is blocked, add a note below it explaining why
- When starting a new phase, break it into granular sub-steps first before doing any work
- Commit progress updates frequently so other instances can see them

### Workflow for Each Session
1. `git pull` -- get latest progress
2. Read `PROGRESS.md` -- see what's done, what's next
3. Do the work
4. Update `PROGRESS.md` -- mark completed steps, add notes
5. `git commit` and `git push` -- share progress

## Problem-Solving Approach

**Always find and implement the proper fix. Hacks and workarounds are a last resort only.**

When encountering a bug or failure:
1. **Investigate the root cause.** Read the relevant kernel source, trace the code path, understand why it fails.
2. **Search for existing upstream patches.** Check lore.kernel.org, patchwork, mailing list archives. Someone may have already fixed this.
3. **Get second opinions.** Use Codex and Gemini for tricky issues. Cross-reference their analysis.
4. **Write a correct fix** that matches how other drivers handle the same problem (e.g., check how i915, amdgpu, or other Qualcomm drivers solve it).
5. **Only as a last resort**, if the proper solution truly cannot be found after thorough research, propose a workaround -- and clearly label it as temporary with a TODO to replace it.

Never propose capping values, disabling features, or skipping code paths as a first response. The goal is upstream-quality code, not "make it work for now."

## Hardware & Driver Knowledge

### Display Pipeline
Two separate display paths on this board:
1. **USB-C DP Alt Mode (DP0 / ae90000):** DPU → DP0 → USB3-DP PHY (fd5000) → PS8830 retimer (LTTPR) → USB-C rear port. Requires full PMIC glink + UCSI + ADSP chain for HPD.
2. **HDMI (mdss_dp3 / aea0000):** Goes to external bridge chip (suspected Realtek RTD2171). Currently disabled in DTB. DT has wrong eDP panel node -- needs replacing with bridge+connector.

### PMIC Glink / UCSI / PDR Chain
All must be =y (built-in) since no module loading in initramfs:
```
QRTR → QRTR_SMD → QMI_HELPERS → PDR_HELPERS → PDR_MSG → PD_MAPPER
→ PMIC_GLINK → UCSI_PMIC_GLINK → TYPEC_DP_ALTMODE → TYPEC_QCOM_PMIC
```
UCSI registration depends on `pd_running` flag from PDR callback for `msm/adsp/charger_pd` service. Without PD_MAPPER=y (and no userspace pd-mapper), the callback never fires and no typec ports are registered.

### DP Link Training with LTTPRs
- **LTTPR = Link-Training Tunable PHY Repeater** (e.g., PS8830 retimer)
- Per-segment training: train each LTTPR individually (farthest-to-closest), then train sink
- LTTPR must be set to **non-transparent mode** (0xaa to DPCD 0xf0003) before per-segment training
- Training patterns: TPS1 (CR phase), TPS4 (EQ phase at HBR3, mandatory for LTTPRs per DP 2.0)
- **Intel blocks HPD during link training** (`intel_hpd_block`) -- MSM driver does not, which causes problems when retimers toggle HPD after failures
- After EQ failure, proper fallback is rate downshift (HBR3→HBR2→HBR→RBR), not lane downshift
- `msm_dp_ctrl_link_lane_down_shift()` resets rate to max -- be aware of this when debugging fallback

### PS8830 Retimer Quirks
- I2C bus 2, address 0x08 on this board
- Known upstream issue: "claims no Level 3 support but actually requires it"
- Always returns 0/0 for voltage/pre-emphasis adjust requests during EQ training
- May toggle HPD after training failure
- AMD has separate `link_dp_training_fixed_vs_pe_retimer.c` for similar retimers (uses vendor-specific DPCD writes), but this targets a different class of retimer, not PS8830 directly
- Codex: don't add generic VS/PE auto-escalation; use targeted quirk keyed on OUI/device-id if needed
- Transparent mode (0x55 to DPCD 0xf0003) is a potential fallback but not preferred for upstream

### Firmware
- Firmware paths use `qcom/x1e80100/` (inherited from parent DTSi), NOT `qcom/x1p42100/`
- Exception: GPU microcode uses `qcom/x1p42100/gen71500_zap.mbn`
- ADSP/CDSP firmware baked into initramfs (v7) for early boot
- Source: Windows `System32/DriverStore/FileRepository/`

### Lessons Learned
- **Verify your hypothesis before patching.** In Boot 12, we initially thought TPS4 wasn't being used for LTTPR EQ training. After patching, we discovered TPS4 WAS already being used -- the Apple adapter supports it. Always check dmesg to confirm the actual code path before writing a fix.
- **Read the full dmesg trace.** AUX transaction logs (DPCD reads/writes) reveal exactly what the driver is doing. Every `0xf00XX AUX` line is an LTTPR register access.
- **Compare with Intel's driver (i915).** It's the most mature DP implementation in the kernel and handles edge cases like HPD blocking, LTTPR transparent mode, and training fallback correctly.
- **`=m` vs `=y` matters in initramfs environments.** If there's no module loading infrastructure, modules are invisible. Every boot failure from Boot 9-12 was caused by a critical driver being `=m` instead of `=y`.
- **The retry/fallback code path matters as much as the training code.** A correct training implementation that can't fall back to lower rates is useless when the highest rate fails.

## Upstream Contribution Rules

All code must be written with upstream submission in mind:
- Device tree files follow `arch/arm64/boot/dts/qcom/` naming conventions
- Compatible strings follow `vendor,device` format (e.g., `lenovo,ideacentre-mini-x-gen10`)
- No hacks or workarounds that wouldn't pass kernel review
- All DTS changes must pass `make CHECK_DTBS=y`
- Patches must pass `scripts/checkpatch.pl`
