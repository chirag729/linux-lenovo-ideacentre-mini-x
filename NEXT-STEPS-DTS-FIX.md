# HDMI via DP1 - Session Progress (2026-02-26)

## Status: Boot 17 deployed, awaiting cold boot test

The Lenovo is powered off. New kernel Image + DTB are on the USB drive.
**Action needed:** Press power button, select GRUB **option 3**.

---

## What Was Done This Session (Boots 14-17)

### Discovery: HDMI is on DP1 (ae98000)
- Confirmed by: (1) Only DP0/DP1 have HPD pinctrl functions in X1E80100 pinctrl; (2) UEFI enables dptx1 clocks (firmware was driving HDMI); (3) GPIO 120 available for edp1_hot
- DP0 (ae90000) = USB-C rear port (via PS8830 retimer at fd5000)
- DP1 (ae98000) = HDMI port (via combo PHY fda000)
- DP3 (aea0000) = internal eDP (nothing physically connected on this desktop)

### Bug 1 Fixed: Clock reparent -EBUSY (Boots 14-16)
**Symptom:** `clk: failed to reparent disp_cc_mdss_dptx1_link_clk_src to fda000.phy::link_clk: -16`
Repeated every ~3 seconds, DP1 stuck in deferred probe, entire DRM subsystem blocked.

**Root cause:** UEFI initialized DP1 for display and left the dptx1 RCG (register clock generator) hardware active. Linux tries to reparent clocks via `assigned-clock-parents` in the DT, but the RCG hardware rejects configuration changes while active (`rcg didn't update its configuration`). This is a hardware-level busy, NOT a Linux enable-count issue -- removing `clk_ignore_unused` from cmdline did NOT help (tested Boot 15).

**Fix applied to DTS (`&mdss_dp1` node):**
```dts
/delete-property/ assigned-clocks;
/delete-property/ assigned-clock-parents;
```
This inherits UEFI's clock configuration (which is already correct -- UEFI was driving HDMI through DP1). Codex confirmed the MSM DP driver never calls `clk_set_parent()` at runtime; it relies entirely on DT preset or firmware state.

**Verification:** Boot 16 showed ZERO clock reparent errors.

### Bug 2 Fixed: aux_bridge infinite deferred probe (Boot 16)
**Symptom:** `ae98000.displayport-controller: deferred probe pending: (reason unknown)`. No DRM devices created (no card0, no connectors).

**Root cause (5-step chain):**
1. Combo PHY (fda000) always calls `drm_aux_bridge_register(dev)` during probe → creates `aux_bridge.aux_bridge.2` auxiliary device
2. aux_bridge driver probes → calls `devm_drm_of_get_bridge(node, 0, 0)` → looks at combo PHY's port@0 endpoint (`usb_1_ss1_qmpphy_out`)
3. port@0 was **empty** (no `remote-endpoint`) → aux_bridge fails with -ENODEV → NO DRM bridge registered for fda000 node
4. DP1 controller probe → `msm_dp_display_probe_tail()` → `devm_drm_of_get_bridge(node, 1, 0)` → follows graph from `mdss_dp1_out` to combo PHY (fda000) → finds remote node but no DRM bridge registered
5. `drm_of_find_panel_or_bridge()` **defaults ret to -EPROBE_DEFER** (line 245 of drm_of.c). Since remote node exists but no bridge found, returns -EPROBE_DEFER. DP driver only ignores -ENODEV → **infinite deferred probe**.

**Key insight:** For DP0, the aux_bridge succeeds because the PS8830 retimer (connected via `usb_1_ss0_qmpphy_out`) provides the next bridge. For DP1, there's no retimer -- just a direct HDMI output.

**Fix applied (upstream-quality, confirmed by both Codex and Gemini):**
1. Added `hdmi-connector` node in board DTS root:
```dts
hdmi-connector {
    compatible = "hdmi-connector";
    type = "a";
    port {
        hdmi_con_in: endpoint {
            remote-endpoint = <&usb_1_ss1_qmpphy_out>;
        };
    };
};
```
2. Connected combo PHY output to HDMI connector:
```dts
&usb_1_ss1_qmpphy_out {
    data-lanes = <0 1 2 3>;
    remote-endpoint = <&hdmi_con_in>;
};
```
3. Added `data-lanes` to DP1 output:
```dts
&mdss_dp1_out {
    data-lanes = <0 1 2 3>;
    link-frequencies = /bits/ 64 <1620000000 2700000000 5400000000 8100000000>;
};
```

### Bug 3 Fixed: DRM_DISPLAY_CONNECTOR=m
The `hdmi-connector` compatible is handled by `drivers/gpu/drm/bridge/display-connector.c` which was built as a module (=m). In our initramfs-only environment with no module loading, this is invisible.

**Fix:** Changed `CONFIG_DRM_DISPLAY_CONNECTOR=y` in defconfig.

---

## Files Modified This Session

### Kernel source (`~/kernel/misaleh-linux`)

**`arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-x-gen10.dts`:**
- Added `hdmi-connector` node in root (type "a", linked to combo PHY output)
- Added `&usb_1_ss1_qmpphy_out` override with `data-lanes = <0 1 2 3>` and `remote-endpoint = <&hdmi_con_in>`
- Added `data-lanes = <0 1 2 3>` to `&mdss_dp1_out`
- Added `/delete-property/ assigned-clocks` and `/delete-property/ assigned-clock-parents` to `&mdss_dp1`
- Added `&mdss_dp1` with `pinctrl-0 = <&edp1_hpd_default>`, `status = "okay"`
- Added `edp1_hpd_default` pinctrl in `&tlmm` for GPIO 120 with `edp1_hot` function
- Added `&usb_1_ss1_qmpphy` with `/delete-property/ mode-switch`, `/delete-property/ orientation-switch`, supplies, `status = "okay"`
- Added `&usb_1_ss1` (status okay) and `&usb_1_ss1_dwc3` (`dr_mode = "host"`)

**`drivers/gpu/drm/msm/dp/dp_display.c`:**
- Removed forced plug event HACK for DP3 (aea0000)
- Added debug breadcrumbs in `hpd_enable` (DRM_DEV_INFO messages for hpd_enable called/done)
- Added PHY init call in `hpd_enable`

**`drivers/gpu/drm/msm/dp/dp_ctrl.c`:**
- Rate fallback fix from previous session: removed HPD check from EQ retry path, always rate-downshift first (HBR3→HBR2→HBR→RBR)

### Project repo (`~/Projects/lenovo-mini-ubuntu`)
- **`kernel/defconfig`** -- `CONFIG_DRM_DISPLAY_CONNECTOR=y` (was `=m`)

### Git state
- Branch: `lenovo-hdmi-dp1` on remote `myfork` (chirag729/linux.git)
- Last push: commit c783abb58 (before Bug 2 and Bug 3 fixes were made)
- **Unpushed changes:** hdmi-connector node, combo PHY output link, assigned-clocks delete, display-connector=y

---

## What to Do After Boot 17

### If Boot 17 succeeds (DP1 probes, DRM card0 created):
```bash
ssh root@192.168.1.15 'dmesg' > testing/boot-logs/2026-02-26-boot17-hdmi-connector/dmesg-full.txt
ssh root@192.168.1.15 'ls /dev/dri/'                         # expect card0, renderD128
ssh root@192.168.1.15 'cat /sys/class/drm/card0-*/status'    # check connector status
ssh root@192.168.1.15 'cat /sys/class/drm/card0-*/modes'     # check available modes
# Check if HDMI monitor shows anything
# Check dmesg for: HPD, AUX communication, link training
```

### If Boot 17 still has deferred probe:
```bash
ssh root@192.168.1.15 'dmesg | grep -i "display.connector\|hdmi.connector\|aux_bridge"'
ssh root@192.168.1.15 'ls /sys/devices/platform/soc@0/fda000.phy/aux_bridge.aux_bridge.2/driver 2>&1'
ssh root@192.168.1.15 'cat /sys/kernel/debug/devices_deferred'
```

### After HDMI works:
- Remove debug breadcrumbs from dp_display.c
- Clean up DP3 (aea0000) -- consider disabling since nothing physically connected
- Test USB-C DP (DP0) link training with rate fallback fix
- Investigate I2C 3:0x5b device (possible HDMI bridge chip)
- Commit all fixes and push to chirag729/linux
- Consider PR to misaleh/linux

---

## Hardware Reference

### Display Pipeline (confirmed)
| Controller | Address | PHY | HPD GPIO | Output |
|-----------|---------|-----|----------|--------|
| DP0 | ae90000 | fd5000 (combo) | 119 (edp0_hot) | USB-C rear (via PS8830) |
| DP1 | ae98000 | fda000 (combo) | 120 (edp1_hot) | HDMI type A |
| DP3 | aea0000 | dedicated DP PHY | 119 (shared) | Internal eDP (unused) |

### I2C Devices
| Bus | Addr | Device |
|-----|------|--------|
| 2 | 0x08 | Parade PS8830 (USB4/DP retimer for DP0) |
| 3 | 0x4f | NXP PTN3222 (USB-C redriver) |
| 3 | 0x5b | Unknown (returns 0xFF, possibly HDMI bridge) |

### GPIOs (display-related)
| GPIO | Function | State |
|------|----------|-------|
| 70 | VREG_EDP_3P3 enable | Claimed by regulator |
| 117 | Unknown (bridge enable?) | Output HIGH, 16mA, UNCLAIMED |
| 119 | DP0 HPD (edp0_hot) | Claimed by DP3 controller |
| 120 | DP1 HPD (edp1_hot) | Configured in our DTS |

### GRUB Menu (`/mnt/usb/EFI/BOOT/grub.cfg`)
1. ACPI boot - no DTB
2. DTB + DRM disabled (safe, telnet works)
3. **DTB + DRM enabled (display test)** ← USE THIS FOR BOOT 17
4. DTB + DRM enabled + nomodeset fallback
5. DTB + DRM + no clk_ignore (DP1/HDMI test)
6. Reboot / Shutdown

---

## Boot History This Session

| Boot | Changes | Result |
|------|---------|--------|
| 14a-c | DP1 enabled in DTS, combo PHY enabled | Clock reparent -EBUSY blocks DP1 probe, NO DRM devices |
| 14d | Added usb_1_ss1 USB controller | Same clock issue + USB dwc3 init failure (missing HS PHY) |
| 15 | Removed `clk_ignore_unused` from cmdline | Clock reparent STILL fails (hardware RCG busy, not Linux), system survived though |
| 16 | Deleted assigned-clocks/parents from mdss_dp1 | Clock errors GONE! But DP1 still deferred (aux_bridge chain discovered) |
| 17 | Added hdmi-connector + linked combo PHY output + DRM_DISPLAY_CONNECTOR=y | **PENDING TEST** |

## Built-in Config Chain (all =y)

| Config | Purpose |
|--------|---------|
| QRTR, QRTR_SMD | IPC to ADSP |
| QCOM_QMI_HELPERS | QMI encoding |
| QCOM_PDR_HELPERS, QCOM_PDR_MSG | Protection Domain Restart |
| QCOM_PD_MAPPER | In-kernel pd-mapper |
| QCOM_PMIC_GLINK | PMIC glink (altmode, UCSI) |
| UCSI_PMIC_GLINK | UCSI over PMIC glink |
| TYPEC_DP_ALTMODE | USB Type-C DP alt mode |
| TYPEC_QCOM_PMIC | Qualcomm PMIC typec |
| DRM_DISPLAY_CONNECTOR | hdmi-connector / dp-connector DRM bridge |

## Firmware Reference

| Windows name | Linux path | Purpose |
|---|---|---|
| qcadsp8380.mbn | qcom/x1e80100/adsp.mbn | ADSP coprocessor |
| adsp_dtbs.elf | qcom/x1e80100/adsp_dtb.mbn | ADSP device tree |
| qccdsp8380.mbn | qcom/x1e80100/cdsp.mbn | CDSP coprocessor |
| cdsp_dtbs.elf | qcom/x1e80100/cdsp_dtb.mbn | CDSP device tree |
| qcdxkmsuc8380.mbn | qcom/x1p42100/gen71500_zap.mbn | GPU microcode |
| adspr.jsn, adsps.jsn, adspua.jsn, battmgr.jsn, cdspr.jsn | qcom/x1e80100/ | Sidecar configs |
