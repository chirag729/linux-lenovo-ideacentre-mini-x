# Claude Code Project Instructions

## Project Overview

This project aims to get Linux (primarily Ubuntu) running on the Lenovo IdeaCentre Mini x Gen 10 with Snapdragon X X1-26-100 processor, and to upstream all work to the mainline Linux kernel so it ships in official distributions.

See `PLAN.md` for the full plan.

## Machine Setup

### Lenovo IdeaCentre Mini x Gen 10 (development host + target device)
- **Claude Code instance:** Windows (PowerShell) -- single instance drives all work, including WSL2 via `wsl -d Ubuntu`
  - Hardware data capture, firmware extraction (Windows-native)
  - Kernel compilation, DTS authoring, DT validation, analysis, patch prep (via WSL2)
- **Build command:** `make -j7` (8 cores @ 3.0GHz, 32GB RAM, use ccache)
- **Kernel source:** `~/kernel/linux` (mainline), `~/kernel/misaleh-linux` (Mostafa's fork)
- **Key advantage:** Can write kernel + DTB directly to EFI partition via `/mnt/c/`

### Netbox (network boot & debug appliance)
- **What it is:** Any always-on Linux machine on the same LAN as the Lenovo
- **IP:** (set `NETBOX_IP` in your environment or replace in commands below)
- **Role:** Network services during test boot cycles. NOT a development host.
- **Services:**
  - TFTP server at `/srv/tftp` (kernel + DTB for network boot)
  - NFS root at `/srv/nfs/lenovo-rootfs`
  - netconsole listener: `nc -u -l -p 6666`
  - SSH client to access Lenovo during headless Linux boot
- **Why it exists:** When the Lenovo reboots into Linux for testing, it can't listen to its own boot log, serve its own network boot files, or provide its own SSH access. The netbox handles all of that.

## Git Workflow

- **NEVER run `git commit` or `git push` yourself.** Instead, provide the user with a one-line commit message and let them commit and push manually.
- Commit messages should be prefixed: `[lenovo-win]` or `[lenovo-wsl]`
- Hardware data goes in `hardware/`
- Never commit proprietary firmware blobs -- only manifests/hashes
- Boot logs go in `testing/boot-logs/` with date prefixes (e.g., `2026-02-15-dmesg.txt`)

## Key Commands

### Building the kernel (WSL2)
```bash
cd ~/kernel/linux
cp ~/Projects/lenovo-mini-ubuntu/kernel/defconfig arch/arm64/configs/ideacentre_defconfig
make ideacentre_defconfig
make -j7 Image dtbs
```

### Building just the device tree (WSL2, fast iteration)
```bash
cd ~/kernel/linux
make dtbs  # Rebuilds only changed DTS files, takes seconds
```

### Deploying kernel for test boot (WSL2)
```bash
# Copy to EFI partition directly:
sudo cp arch/arm64/boot/Image /mnt/c/efi/EFI/BOOT/
sudo cp arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-mini-x.dtb /mnt/c/efi/dtbs/

# OR push to netbox TFTP server:
rsync -av arch/arm64/boot/Image arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-mini-x.dtb \
  user@netbox:/srv/tftp/
```

### Listening for netconsole on netbox
```bash
nc -u -l -p 6666 | tee testing/boot-logs/$(date +%Y%m%d-%H%M).txt
```

### Hardware audit from Windows (Lenovo)
```powershell
# See scripts/windows-hardware-audit.ps1
```

### Hardware audit from Linux (Lenovo)
```bash
# See scripts/hardware-audit.sh
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

## Upstream Contribution Rules

All code must be written with upstream submission in mind:
- Device tree files follow `arch/arm64/boot/dts/qcom/` naming conventions
- Compatible strings follow `vendor,device` format (e.g., `lenovo,ideacentre-mini-x-gen10`)
- No hacks or workarounds that wouldn't pass kernel review
- All DTS changes must pass `make CHECK_DTBS=y`
- Patches must pass `scripts/checkpatch.pl`
