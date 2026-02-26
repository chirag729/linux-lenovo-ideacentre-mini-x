# Boot 8 Analysis - DRM with DP1 Disabled

## Date: 2026-02-26

## Changes from Boot 7
- DTB: DP1 (aea0000, eDP) set to `status = "disabled"` via dtc decompile/edit/recompile on Pi 5
- Initramfs v6: Added Pi's ed25519 public key to `/root/.ssh/authorized_keys`

## Results

### SUCCESS: DRM card created
- Component aggregate `ae01000.display-controller` **bound successfully**
- `bound ae90000.displayport-controller (ops msm_dp_display_comp_ops)`
- `bound 3d00000.gpu (ops a3xx_ops)` - GPU (Adreno 67.3.12.0) also bound
- DRM card0 created with DP-1 connector and renderD128
- Two CRTCs (crtc-0, crtc-1) initialized

### SUCCESS: SSH key auth works
- `ssh -i ~/.ssh/id_ed25519 root@192.168.1.15` connects immediately
- Password auth still broken but no longer matters

### ISSUE: DP-1 connector shows "disconnected"
- `[drm:msm_dp_bridge_detect] link_ready = false`
- `[CONNECTOR:34:DP-1] disconnected`
- No EDID data available
- No HPD (hot-plug detect) signal received

### Root Cause: Missing kernel modules
- `CONFIG_TYPEC_DP_ALTMODE=m` - DP alt mode driver is a MODULE
- `CONFIG_TYPEC_QCOM_PMIC=m` - Qualcomm PMIC typec driver is a MODULE
- Initramfs has NO modules → these drivers never load
- Without DP alt mode driver, USB-C connector can't negotiate DP mode
- Without DP mode negotiation, HPD signal never reaches DP controller

### PMIC Glink Status
- `qcom_pmic_glink` probed successfully (built-in)
- Has altmode, power-supply, ucsi sub-devices
- BUT: `Failed to create device link (0x180) with supplier 2-0008` (PS8830 retimer)
- AND: `Failed to create device link (0x180) with supplier a600000.usb`
- These device link failures may be related to the missing typec modules

### GPU Status
- Adreno 67.3.12.0 bound
- Missing firmware: `gen71500_sqe.fw` (not critical for display output)
- Using dummy regulators for vdd/vddcx

### I2C Devices (confirmed bound)
- 2-0008: PS8830 retimer → `ps883x_retimer` driver (BOUND)
- 3-004f: PTN3222 redriver → `ptn3222` driver (BOUND)
- PS8830 has `aux_bridge` child device (bound to `aux_bridge.aux_bridge` driver)

### Display Path Architecture (confirmed)
```
PMIC Glink connector@0 (usb-c-connector)
  → port@0 → USB (a600000.usb)
  → port@1 → PS8830 retimer port@0
  → port@2 → PS8830 retimer port@2

PS8830 retimer has aux_bridge child → needed for DP AUX passthrough

DPU (ae01000) → port@0 → DP0 (ae90000) → DP PHY (fd5000)
```

## Fix: Rebuild kernel with built-in typec drivers
```
CONFIG_TYPEC_DP_ALTMODE=y  (was =m)
CONFIG_TYPEC_QCOM_PMIC=y   (was =m)
```
Building on Pi 5 with `make -j4 CC="ccache gcc"` from Mostafa's fork (6.19.0-rc4).
