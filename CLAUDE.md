# Claude Code Project Instructions

## Project Overview

This project aims to get Linux (primarily Ubuntu) running on the Lenovo IdeaCentre Mini x Gen 10 with Snapdragon X X1-26-100 processor, and to upstream all work to the mainline Linux kernel so it ships in official distributions.

See `PLAN.md` for the full plan.

## Three-Instance Setup

There are three Claude Code instances working on this project, on two physical machines:

### Instance 1: Raspberry Pi 5 (always-on server + backup build)
- **Location:** `/home/pi/Projects/lenovo-mini-ubuntu`
- **Kernel source:** `~/kernel/linux` (mainline), `~/kernel/misaleh-linux` (Mostafa's fork)
- **IP:** 192.168.1.14
- **Role:** Always-on infrastructure (TFTP, NFS, netconsole listener), analysis, patch prep, backup builds
- **Build command:** `make -j3` (4 cores, 16GB RAM + 8GB swap, use ccache)
- **Services:**
  - TFTP server at `/srv/tftp` (kernel + DTB for network boot)
  - NFS root at `/srv/nfs/lenovo-rootfs`
  - netconsole listener: `nc -u -l -p 6666`

### Instance 2: Lenovo Windows (PowerShell)
- **Role:** Hardware data capture, firmware extraction
- **When to use:** Phase 0 and Phase 1 (Windows-side hardware audit), Phase 5 (firmware extraction)
- **Output:** Commits to `hardware/` in this repo

### Instance 3: Lenovo WSL2 (Ubuntu ARM64) -- PRIMARY BUILD HOST
- **Role:** Kernel compilation, DTS authoring, DT validation
- **Build command:** `make -j7` (8 cores @ 3.0GHz, 32GB RAM, use ccache)
- **Kernel source:** `~/kernel/linux` (mainline), `~/kernel/misaleh-linux` (Mostafa's fork)
- **Key advantage:** Can write kernel + DTB directly to EFI partition via `/mnt/c/`
- **Also clones this repo:** `~/Projects/lenovo-mini-ubuntu`

## Git Workflow

- All three instances share this repo
- **NEVER run `git commit` or `git push` yourself.** Instead, provide the user with a one-line commit message and let them commit and push manually.
- Commit messages should be prefixed: `[pi]`, `[lenovo-win]`, or `[lenovo-wsl]`
- Hardware data goes in `hardware/`
- Never commit proprietary firmware blobs -- only manifests/hashes
- Boot logs go in `testing/boot-logs/` with date prefixes (e.g., `2026-02-15-dmesg.txt`)

## Key Commands

### Building the kernel (WSL2, primary)
```bash
cd ~/kernel/linux
cp ~/Projects/lenovo-mini-ubuntu/kernel/defconfig arch/arm64/configs/ideacentre_defconfig
make ideacentre_defconfig
make -j7 Image dtbs
```

### Building the kernel (Pi, backup)
```bash
cd ~/kernel/linux
cp /home/pi/Projects/lenovo-mini-ubuntu/kernel/defconfig arch/arm64/configs/ideacentre_defconfig
make ideacentre_defconfig
make -j3 Image dtbs
```

### Building just the device tree (either host, fast iteration)
```bash
cd ~/kernel/linux
make dtbs  # Rebuilds only changed DTS files, takes seconds
```

### Deploying kernel for test boot (WSL2)
```bash
# Copy to EFI partition directly:
sudo cp arch/arm64/boot/Image /mnt/c/efi/EFI/BOOT/
sudo cp arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-mini-x.dtb /mnt/c/efi/dtbs/

# OR push to Pi TFTP server:
rsync -av arch/arm64/boot/Image arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-mini-x.dtb \
  pi@192.168.1.14:/srv/tftp/
```

### Listening for netconsole on Pi
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

1. **netconsole** -- kernel console over Ethernet to Pi (add to cmdline: `netconsole=@/eth0,6666@192.168.1.14/`)
2. **SSH over Ethernet** -- interactive shell once rootfs is up
3. **Blind boot + capture script** -- `scripts/hardware-audit.sh` writes to partition

## Progress Tracking

Progress is tracked in `PROGRESS.md` at the repo root. This file contains granular step-by-step checklists for every task, including setup, configuration, and verification steps.

### Rules for Progress Tracking
- **Every instance** must update `PROGRESS.md` when completing a step
- Mark steps `[x]` only when verified working, not just attempted
- Add the date and instance tag when completing a step: `[x] (2026-02-15, pi)`
- If a step fails or is blocked, add a note below it explaining why
- When starting a new phase, break it into granular sub-steps first before doing any work
- Commit progress updates frequently so other instances can see them

### Workflow for Each Session
1. `git pull` -- get latest progress from other instances
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
