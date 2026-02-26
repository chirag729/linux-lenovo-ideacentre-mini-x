# Next Steps: Display & Firmware (2026-02-26)

## Current Status

Boot 12 achieved:
- **UCSI typec port0 registered** -- full PDR chain works (QRTR_SMD=y, PD_MAPPER=y)
- **DP alt mode active** (SVID 0xff01) on port0
- **USB-C partner detected** (Apple USB-C to HDMI adapter)
- **HPD fired**, DP link training started
- **CR (phase 1) succeeded** at HBR3 / 2 lanes / v=0, p=0 through PS8830 LTTPR
- **EQ (phase 2) FAILED** on PS8830 LTTPR -- retimer always returns 0/0 adjust requests
- **Root cause:** Two bugs in MSM DP driver retry loop:
  1. HPD deasserts after LTTPR EQ failure (PS8830 toggles HPD), breaking retry loop
  2. Driver never falls back to lower link rates (HBR2/HBR/RBR) after LTTPR failure

## Fix Applied for Boot 13

Modified `drivers/gpu/drm/msm/dp/dp_ctrl.c` in `msm_dp_ctrl_on_link()`:
- **Removed HPD check** from EQ failure retry path (Intel blocks HPD during training too)
- **Always rate-downshift first** after EQ failure (HBR3→HBR2→HBR→RBR)
- **Removed stale DPRX link status read** (meaningless after LTTPR failure)
- Loop is bounded by `link_train_max_retries=5`, so can't loop forever

Expected Boot 13 sequence:
1. HBR3 LTTPR EQ fails (PS8830 still returns 0/0) → rate downshift to HBR2
2. HBR2 LTTPR training → may succeed (lower rate = less signal tuning needed)
3. If HBR2 works → sink training → display output!
4. If HBR2 fails → HBR → RBR → eventually succeed or exhaust retries

## What's on the USB

- `Image` -- kernel with EQ retry fix + full PDR chain built-in
- `dtb/x1p42100-lenovo-ideacentre-x-gen10.dtb` -- mdss_dp3 (aea0000) disabled
- `initramfs.cpio.gz` -- v7 with firmware (adsp.mbn, cdsp.mbn, gen71500_zap.mbn)

## Boot 13 Check

```bash
ssh root@192.168.1.15
dmesg | grep -i "link rate\|new rate\|link training\|channel eq\|EQ done"
cat /sys/class/drm/card0-DP-1/status   # connected?
cat /sys/class/drm/card0-DP-1/modes    # if connected, what modes?
dmesg | grep -i "rate_down_shift\|reinitialize"  # verify retry happening
```

## Built-in Config Chain (all =y)

| Config | Purpose |
|--------|---------|
| QRTR | QRTR IPC router |
| QRTR_SMD | SMD transport for QRTR (talks to ADSP) |
| QCOM_QMI_HELPERS | QMI encoding/decoding |
| QCOM_PDR_HELPERS | Protection Domain Restart helpers |
| QCOM_PDR_MSG | PDR QMI messages |
| QCOM_PD_MAPPER | In-kernel pd-mapper (service locator provider) |
| QCOM_PMIC_GLINK | PMIC glink (altmode, UCSI, battmgr) |
| UCSI_PMIC_GLINK | UCSI over PMIC glink |
| TYPEC_DP_ALTMODE | USB Type-C DP alt mode |
| TYPEC_QCOM_PMIC | Qualcomm PMIC typec driver |

## Two Display Paths

### Path 1: USB-C DP Alt Mode (DP0 / ae90000) -- ACTIVE
- Wiring: DPU → DP0 → USB3-DP PHY (fd5000) → PS8830 retimer → USB-C rear port
- Chain: ADSP → PMIC glink → PDR → UCSI → typec port → DP alt mode → HPD → link training
- Status: Link training reaches PS8830, CR OK, EQ fails at HBR3 → Boot 13 has rate fallback fix
- Test: Apple USB-C to HDMI adapter plugged into rear USB-C port

### Path 2: HDMI via mdss_dp3 (aea0000) -- needs DT work
- **Currently disabled** in DTB (we disabled it to fix component aggregate)
- Codex analysis suggests HDMI goes through this controller via an external bridge chip
- The DT currently has an eDP panel child (wrong for desktop)
- **Fix:** Re-enable mdss_dp3, remove eDP panel, add HDMI bridge+connector graph

## Boot History

| Boot | Config/Fix | Result |
|------|-----------|--------|
| 8 | (initial DRM test) | DRM card0 created, DP-1 disconnected |
| 9 | TYPEC_DP_ALTMODE=y, TYPEC_QCOM_PMIC=y | Aux bus drivers bound, still disconnected |
| 10 | NTFS3_FS=y | Firmware extracted, ADSP/CDSP started manually |
| 11 | QRTR_SMD=y + firmware in initramfs | ADSP/CDSP at boot, UCSI still no typec ports |
| 12 | QCOM_PD_MAPPER=y | UCSI works! typec port0 registered, DP alt mode active, link training fails (EQ at HBR3) |
| 13 | EQ retry fix (remove HPD check, rate fallback) | **Pending** |

## PS8830 LTTPR Details (from Boot 12 dmesg)

- LTTPR revision: DP 2.0 (0x20)
- Max link rate: HBR3 (0x1e = 8.1 Gbps)
- PHY repeater count: 1 (0x80)
- I2C address: bus 2, 0x08
- Non-transparent mode set correctly (0xaa written to 0xf0003)
- CR phase: succeeds with TPS1 at v=0, p=0
- EQ phase: fails with TPS4 -- adjust request registers (0xf0033) always 0x00
- Known upstream issue: "PS8830 claims no Level 3 support but actually requires it"

## If Boot 13 Still Fails

If all rates fail EQ on the LTTPR:
1. Try transparent LTTPR mode (write 0x55 to DPCD 0xf0003 instead of 0xaa)
2. Add PS8830-specific voltage/pre-emphasis quirk (keyed on OUI at 0xf0003)
3. Investigate HDMI path (Path 2) as alternative -- no LTTPR involved

## Firmware Reference

Extracted from Windows, installed as:
| Windows name | Linux path | Purpose |
|---|---|---|
| qcadsp8380.mbn | qcom/x1e80100/adsp.mbn | ADSP coprocessor |
| adsp_dtbs.elf | qcom/x1e80100/adsp_dtb.mbn | ADSP device tree |
| qccdsp8380.mbn | qcom/x1e80100/cdsp.mbn | CDSP coprocessor |
| cdsp_dtbs.elf | qcom/x1e80100/cdsp_dtb.mbn | CDSP device tree |
| qcdxkmsuc8380.mbn | qcom/x1p42100/gen71500_zap.mbn | GPU microcode |
| adspr.jsn, adsps.jsn, adspua.jsn, battmgr.jsn, cdspr.jsn | qcom/x1e80100/ | Sidecar configs |
