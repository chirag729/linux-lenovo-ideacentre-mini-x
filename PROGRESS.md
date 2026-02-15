# Progress Tracker

This file tracks granular progress. See `PLAN.md` for the full plan and context.

Always `git pull` before reading, `git push` after updating.

---

## Phase 0: Prerequisites & Environment Setup

### 0.1 Hardware & Accounts
- [x] Obtain Lenovo IdeaCentre Mini x Gen 10 (2026-02-15, user)
- [x] Create GitHub repo: `chirag729/linux-lenovo-ideacentre-mini-x` (2026-02-15)
- [x] Push initial repo with PLAN.md, CLAUDE.md, scripts (2026-02-15)
- [ ] Confirm Windows 11 on ARM is installed and fully updated on Lenovo

### 0.2 Set Up Lenovo Windows Instance
- [ ] Install git for Windows ARM64 on Lenovo
  - Download from: https://git-scm.com/download/win
- [ ] Install Claude Code on Lenovo Windows (PowerShell)
- [ ] Generate SSH key on Lenovo Windows for GitHub
  ```powershell
  ssh-keygen -t ed25519 -C "lenovo-win-lenovo-linux" -f $env:USERPROFILE\.ssh\id_ed25519
  ```
- [ ] Add Lenovo Windows SSH public key to GitHub
- [ ] Clone the repo on Lenovo Windows:
  ```powershell
  cd ~\Projects
  git clone git@github.com:chirag729/linux-lenovo-ideacentre-mini-x.git
  ```
- [ ] Verify Claude Code can run PowerShell commands on Lenovo
- [ ] Test git push from Lenovo Windows

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

- [ ] Run `scripts/windows-hardware-audit.ps1` on Lenovo
- [ ] Review output in `hardware/` directory
- [ ] Commit and push results

---

## Phase 1: Hardware Audit & Identification

(Will be broken into granular steps once Phase 0 is complete and we can see the hardware data)

- [ ] Windows-side audit complete (Phase 0.6)
- [ ] First Linux boot on Lenovo
- [ ] Linux-side audit complete
- [ ] Cross-reference analysis (WSL2)
- [ ] Hardware map document produced

---

## Blocked / Notes

Record any blockers, surprises, or decisions here:

- (none yet)
