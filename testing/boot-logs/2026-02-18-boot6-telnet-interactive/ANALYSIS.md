# Boot 6 Analysis -- Interactive Telnet Session (2026-02-18)

## Summary

First ever interactive Linux session on the Lenovo IdeaCentre Mini x Gen 10 (Snapdragon X).
Access via telnet (port 23) from Pi netbox. SSH (dropbear) connects but rejects login
due to /root permissions and password issues (NOT the ld-linux ELOOP from earlier boots).

**Kernel:** 6.19.0-rc4-g740f9e80d577 (Mostafa Saleh's `lenovo` branch)
**DT model:** "Lenovo IdeaCentre X Gen 10 Snapdragon"
**DT compatible:** `lenovo,ideacentre-x-gen10`, `qcom,x1p42100`
**Initramfs:** v4 (pi-20260218-204435)
**Boot time to shell:** ~29s (carrier at 28.3s, DHCP at 28.5s, shell at 28.7s)

## Hardware Status

### Working
| Component | Details | Driver |
|-----------|---------|--------|
| CPU | 8x Oryon (4x perf variant 0x2 + 4x eff variant 0x1) | - |
| RAM | 32GB (8279216 pages) | - |
| Ethernet | RTL8168h, MAC 18:3d:2d:ce:9f:ac | r8169 |
| NVMe | Samsung MZVL8512HDLU-00BLL, FW 9L2QKXD7, 500GB | nvme |
| USB | 4x xHCI, GL3510 hubs, keyboard detected | xhci-hcd |
| efifb | 1920x1080x32 at 0xe4800000 | efifb |
| UART | ttyMSM0 at 0x894000, Qualcomm GENI | msm_serial |
| PCIe | 3x root ports (17cb:0111) | pcieport |
| Thermals | All zones reporting (SoC 21-23C, PMICs 37C) | qcom-spmi-adc-tm5 |
| Watchdog | SBSA GWDT, 10s timeout, auto-pinged | sbsa_gwdt |
| SPMI | PMIC arbiter v7, multiple PMICs | spmi-pmic-arb |
| I2C | 4x Geni-I2C, ps8830 retimer, ptn3222 redriver, 3x HID | - |

### Not Working / Disabled
| Component | Details | Issue |
|-----------|---------|-------|
| Display/DRM | `drm.modeset=0` + `nomodeset` | Intentionally disabled; efifb works |
| WiFi | FastConnect 7800 (17cb:1107) | No driver bound (needs ath12k + firmware) |
| ADSP | remoteproc0 | Firmware `qcom/x1e80100/adsp.mbn` not found (ENOENT) |
| CDSP | remoteproc1 | Firmware `qcom/x1e80100/cdsp.mbn` not found (ENOENT) |
| Audio | LPASS LPI pinctrl | "Failed to get clk 'core'" (deferred probe) |
| RTC | c42d000.spmi:pmic@0:rtc@6100 | Deferred probe (unknown reason) |
| GPU | gpu@3d00000, gmu@3d6a000 | Not probed (DRM disabled) |

### USB Mouse Bug
SIGMACHIP mouse (1c4f:0034) connects/disconnects every ~2.5s, flooding dmesg.
Not a Linux issue -- likely faulty cheap mouse or USB hub compatibility.

## Display Architecture (from DT and runtime)

### Platform Devices Present
- `ae00000.display-subsystem` (MDSS) -- in IOMMU group 5
- `ae01000.display-controller` (DPU)
- `ae90000.displayport-controller` (DP0 -- USB-C alt mode via PHY@fd5000)
- `aea0000.displayport-controller` (DP1 -- has aux-bus/panel child, likely eDP)

### Retimers (I2C)
- `ps8830` -- Parade PS8830 DP retimer
- `ptn3222` -- NXP PTN3222 USB Type-C redriver

### Retimer Regulators
| Regulator | State | Voltage |
|-----------|-------|---------|
| VREG_RTMR0_1P15 | **enabled** | 1.15V |
| VREG_RTMR0_1P8 | **enabled** | 1.8V |
| VREG_RTMR0_3P3 | **enabled** | 3.3V |
| VREG_RTMR1_1P15 | disabled | 1.15V |
| VREG_RTMR1_1P8 | disabled | 1.8V |
| VREG_RTMR1_3P3 | disabled | 3.3V |
| VREG_RTMR2_1P15 | disabled | 1.15V |
| VREG_RTMR2_1P8 | disabled | 1.8V |
| VREG_RTMR2_3P3 | disabled | 3.3V |
| VREG_EDP_3P3 | disabled | 3.3V |

**Key finding:** Only retimer 0 is powered. Retimers 1 and 2 and eDP supply are all disabled.

### Power Domains (Display-Related)
| Domain | Status | Children |
|--------|--------|----------|
| mdss_gdsc | **OFF** | ae00000.display-subsystem (suspended) |
| mdss_int2_gdsc | **OFF** | - |
| gpu_cc_gx_gdsc | **OFF** | - |
| gpu_cc_cx_gdsc | **OFF** | 3da0000.iommu (suspended) |
| mmcx | ON | DPU, DP0, DP1 (all suspended), video/disp clk controllers |

### Clock Controllers (Pending)
- `gcc-x1e80100 100000.clock-controller` -- sync_state pending due to `3d6a000.gmu` (GPU)
- `gpucc-x1p42100 3d90000.clock-controller` -- sync_state pending due to `3d6a000.gmu`

### efifb Details
```
efifb: framebuffer at 0xe4800000, using 8100k, total 8100k
efifb: mode is 1920x1080x32, linelength=7680, pages=1
```

## NVMe (Windows) Partitions
| Partition | Size | Likely Contents |
|-----------|------|-----------------|
| nvme0n1p1 | 260MB | EFI System Partition |
| nvme0n1p2 | 16MB | Microsoft Reserved |
| nvme0n1p3 | 474GB | Windows C: (NTFS) |
| nvme0n1p4 | 2GB | Windows Recovery |

## Firmware Status
Remoteproc firmware expected at `qcom/x1e80100/` (not `qcom/x1p42100/`):
- `adsp.mbn` -- Audio DSP (needed for audio, possibly display handoff)
- `cdsp.mbn` -- Compute DSP
- Missing: `wpss.mbn` (WiFi processor, noted in first boot but not attempted here)

## PMIC Glink Issues
```
Failed to create device link (0x180) with supplier 2-0008 for /pmic-glink/connector@0
Failed to create device link (0x180) with supplier a600000.usb for /pmic-glink/connector@0
```
Device `2-0008` is likely the Type-C mux on I2C bus 2. This affects USB-C alt-mode DP.

## Dropbear SSH Issue (SOLVED)
Previous boots showed ld-linux ELOOP. Boot 6 shows dropbear IS running but:
1. `/root must be owned by user or root, and not writable by group or others`
2. Password auth fails (root password not set correctly)

**Fix:** Set correct /root permissions (0700 root:root) and either set root password
in /etc/shadow or use dropbear key-based auth.

## Next Steps
1. Fix SSH: correct /root perms + root password in initramfs
2. Try boot WITHOUT `nomodeset`/`drm.modeset=0` to let DRM_MSM probe
3. Extract firmware from Windows partition (adsp.mbn, cdsp.mbn)
4. Investigate PMIC glink connector@0 / Type-C mux issue
5. Fix the USB mouse (unplug it, or blacklist device)
