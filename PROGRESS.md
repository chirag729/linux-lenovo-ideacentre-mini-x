# Progress Tracker

This file tracks granular progress across all instances. See `PLAN.md` for the full plan and context.

Updated by all three Claude Code instances. Always `git pull` before reading, `git push` after updating.

---

## Phase 0: Prerequisites & Environment Setup

### 0.1 Hardware & Accounts
- [x] Obtain Lenovo IdeaCentre Mini x Gen 10 (2026-02-15, user)
- [x] Create GitHub repo: `chirag729/linux-lenovo-ideacentre-mini-x` (2026-02-15, pi)
- [x] Generate SSH key on Pi for GitHub (2026-02-15, pi)
- [x] Push initial repo with PLAN.md, CLAUDE.md, scripts (2026-02-15, pi)
- [ ] Confirm Windows 11 on ARM is installed and fully updated on Lenovo

### 0.2 Set Up Lenovo Windows Instance
- [ ] Install Claude Code on Lenovo Windows (PowerShell)
  - Download from: https://claude.ai/download
  - Or via: `npm install -g @anthropic-ai/claude-code`
- [ ] Install git for Windows ARM64 on Lenovo
  - Download from: https://git-scm.com/download/win
- [ ] Generate SSH key on Lenovo Windows for GitHub
  ```powershell
  ssh-keygen -t ed25519 -C "lenovo-win-lenovo-linux" -f $env:USERPROFILE\.ssh\id_ed25519
  ```
- [ ] Add Lenovo Windows SSH public key to GitHub (same account)
- [ ] Clone the repo on Lenovo Windows:
  ```powershell
  cd ~\Projects
  git clone git@github.com:chirag729/linux-lenovo-ideacentre-mini-x.git
  ```
- [ ] Verify Claude Code can run PowerShell commands on Lenovo
- [ ] Run a test commit from Lenovo Windows to confirm git push works:
  ```powershell
  cd ~\Projects\linux-lenovo-ideacentre-mini-x
  echo "test" > hardware\test.txt
  git add hardware\test.txt
  git commit -m "[lenovo-win] Test commit from Lenovo Windows"
  git push
  ```
- [ ] Delete the test file and commit

### 0.3 Set Up Lenovo WSL2 Instance
- [ ] Install WSL2 on Lenovo:
  ```powershell
  wsl --install -d Ubuntu
  ```
- [ ] Set WSL2 username and password
- [ ] Update WSL2 Ubuntu:
  ```bash
  sudo apt update && sudo apt upgrade -y
  ```
- [ ] Install build dependencies in WSL2:
  ```bash
  sudo apt install build-essential flex bison libssl-dev libelf-dev bc \
    ccache device-tree-compiler python3-pip git
  pip3 install --user dtschema yamllint
  ```
- [ ] Configure ccache in WSL2:
  ```bash
  echo 'export PATH="/usr/lib/ccache:$PATH"' >> ~/.bashrc
  source ~/.bashrc
  ccache --max-size=10G
  ```
- [ ] Install Claude Code in WSL2
- [ ] Generate SSH key in WSL2 for GitHub:
  ```bash
  ssh-keygen -t ed25519 -C "lenovo-wsl-lenovo-linux"
  ```
- [ ] Add WSL2 SSH public key to GitHub
- [ ] Clone project repo in WSL2:
  ```bash
  mkdir -p ~/Projects
  git clone git@github.com:chirag729/linux-lenovo-ideacentre-mini-x.git ~/Projects/lenovo-mini-ubuntu
  ```
- [ ] Clone kernel sources in WSL2:
  ```bash
  mkdir -p ~/kernel
  git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git ~/kernel/linux
  git clone -b lenovo https://github.com/misaleh/linux.git ~/kernel/misaleh-linux
  ```
- [ ] Clone dtbloader in WSL2:
  ```bash
  git clone https://github.com/TravMurav/dtbloader.git ~/kernel/dtbloader
  ```
- [ ] Verify WSL2 can access Windows filesystem:
  ```bash
  ls /mnt/c/
  ```
- [ ] Verify build works in WSL2:
  ```bash
  cd ~/kernel/linux && make defconfig && make -j7 Image
  ```
  Note: this will take ~15-25 minutes for first build
- [ ] Run a test commit from WSL2:
  ```bash
  cd ~/Projects/lenovo-mini-ubuntu
  git commit --allow-empty -m "[lenovo-wsl] Test commit from WSL2"
  git push
  ```

### 0.4 Set Up Pi 5 Services
- [x] Install build tools on Pi (build-essential, flex, bison, etc.) (2026-02-15, pi)
- [x] Install ccache on Pi (2026-02-15, pi)
- [x] Set up 8GB swap on Pi (2026-02-15, pi)
- [x] Install tftpd-hpa on Pi (2026-02-15, pi)
- [x] Install nfs-kernel-server on Pi (2026-02-15, pi)
- [x] Install screen on Pi (2026-02-15, pi)
- [x] Configure ccache (2026-02-15, pi): max-size=10G, PATH configured in .bashrc
- [ ] Clone kernel sources on Pi:
  ```bash
  mkdir -p ~/kernel
  git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git ~/kernel/linux
  git clone -b lenovo https://github.com/misaleh/linux.git ~/kernel/misaleh-linux
  ```
- [ ] Clone dtbloader on Pi:
  ```bash
  git clone https://github.com/TravMurav/dtbloader.git ~/kernel/dtbloader
  ```
- [ ] Configure TFTP server:
  ```bash
  sudo nano /etc/default/tftpd-hpa
  # Set: TFTP_DIRECTORY="/srv/tftp"
  sudo mkdir -p /srv/tftp
  sudo systemctl restart tftpd-hpa
  sudo systemctl enable tftpd-hpa
  ```
- [ ] Verify TFTP is running: `sudo systemctl status tftpd-hpa`
- [ ] Configure NFS server:
  ```bash
  sudo mkdir -p /srv/nfs/lenovo-rootfs
  # Add to /etc/exports: /srv/nfs/lenovo-rootfs *(rw,no_root_squash,no_subtree_check)
  sudo exportfs -ra
  sudo systemctl restart nfs-kernel-server
  sudo systemctl enable nfs-kernel-server
  ```
- [ ] Verify NFS is running: `sudo systemctl status nfs-kernel-server`
- [ ] Test git pull/push from Pi works

### 0.5 Verify Cross-Machine Communication
- [ ] From Pi, confirm Lenovo is reachable: `ping <lenovo-ip>`
- [ ] From Lenovo WSL2, confirm Pi is reachable: `ping 192.168.1.14`
- [ ] From Lenovo WSL2, confirm SSH to Pi works: `ssh pi@192.168.1.14`
- [ ] From Lenovo WSL2, confirm rsync to Pi works:
  ```bash
  rsync -av --dry-run ~/kernel/linux/Makefile pi@192.168.1.14:/tmp/
  ```
- [ ] Both instances can `git pull` each other's commits

---

## Phase 0.6: Windows Hardware Audit

Tracked here so the Lenovo Windows instance knows exactly what to do.

- [ ] Run `scripts/windows-hardware-audit.ps1` on Lenovo
- [ ] Review output in `hardware/` directory
- [ ] Commit and push results: `git commit -m "[lenovo-win] Phase 0: Windows hardware audit"`
- [ ] Pi instance pulls and analyzes results

---

## Phase 1: Hardware Audit & Identification

(Will be broken into granular steps once Phase 0 is complete and we can see the hardware data)

- [ ] Windows-side audit complete (Phase 0.6)
- [ ] First Linux boot on Lenovo
- [ ] Linux-side audit complete
- [ ] Cross-reference analysis (Pi)
- [ ] Hardware map document produced

---

## Blocked / Notes

Record any blockers, surprises, or decisions here:

- (none yet)
