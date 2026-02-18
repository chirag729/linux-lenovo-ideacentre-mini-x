# Boot 7 Analysis -- DRM Enabled (2026-02-18)

## Summary

First boot with DRM_MSM allowed to probe (`nomodeset` and `drm.modeset=0` removed).
Kernel cmdline: `clk_ignore_unused pd_ignore_unused console=tty0 earlycon earlyprintk loglevel=8 keep_bootcon drm.debug=0x1ff log_buf_len=8M`

**Result:** DPU probed successfully, but DRM card NOT created. Component aggregate never bound.

## Key Findings

### DRM Probe Sequence
1. `drm_core_init` -- DRM core initialized
2. `msm_drm_register` -- MSM DRM platform driver registered
3. `msm_mdp_register` -- DPU/MDP sub-driver registered
4. `msm_dsi_register` -- DSI sub-driver registered (no DSI on this board)
5. `dpu_dev_probe` -- DPU mapped address space successfully
6. `dpu_dev_probe` -- "VBIF NRT is not defined" (warning, non-critical)
7. Only DP1 (aea0000, type=14=eDP) did a PHY init cycle, then immediately exited
8. DP0 (ae90000, USB-C) -- **no DRM activity at all**
9. `VREG_EDP_3P3: disabling` at t=35s -- regulator cleaned up

### Component Framework -- ROOT CAUSE
```
aggregate: ae01000.display-controller         -> not bound
components:
  ae90000.displayport-controller              -> not bound (registered)
  (unknown)                                   -> not registered
  (unknown)                                   -> not registered
```

The DPU aggregate expects 3 components but only 1 (DP0) registered.
**The aggregate CANNOT bind until ALL expected components register.**

### DPU Port Graph (from DT)
| DPU Port | Connects To | Controller | DT Status | Component |
|----------|-------------|------------|-----------|-----------|
| port@0 | ae90000 (DP0) | USB-C DP alt mode | okay | registered, not bound |
| port@4 | ae98000 (DP2) | - | **disabled** | N/A (disabled) |
| port@5 | aea0000 (DP1) | eDP panel | okay | **NOT registered** |
| port@6 | ae9a000 (DP3) | - | **disabled** | N/A (disabled) |

### Why DP1 Didn't Register as Component
DP1 (aea0000) has:
- Platform driver bound (has `driver` symlink)
- PHY supplier: `phy-aec5a00.phy.0` (dedicated eDP PHY, NOT the USB-C combo PHY)
- AUX bus created: `aux-aea0000.displayport-controller`
- Panel child in DT: aux-bus/panel with `enable-gpios`, `power-supply`
- **BUT:** No actual eDP panel exists (this is a desktop!)

The DP driver likely probed the AUX bus, tried to find the panel, failed (no HPD),
and returned a probe deferral or error that prevented component_add().

### Why No DRM Card Was Created
Without all 3 components registered, `msm_drm_bind()` is never called. This means:
- No DRM card (`/sys/class/drm/card0`)
- No `/dev/dri/` directory
- No connectors, encoders, or CRTCs
- efifb stays active (good -- screen doesn't go black)

### SSH Status
Still broken -- password authentication fails. Need to investigate further.
Dropbear connects (no more ELOOP) but rejects all passwords.

## Fix Path

### Short-term: DTS modification
Edit `x1p42100-lenovo-ideacentre-x-gen10.dts` to:
1. **Disable DP1 (aea0000)** -- no eDP panel on a desktop
2. **Remove/disable the eDP panel node** under DP1's aux-bus
3. **Remove DPU port@5** endpoint (or disable DP1 so component isn't expected)
4. Ports 4 and 6 should be harmless (DP2/DP3 already disabled)

This should reduce expected components to just DP0 (ae90000), allowing the
aggregate to bind and create a DRM card.

### Medium-term: HDMI bridge identification
The HDMI port is NOT described in the current DTS:
- No bridge chip compatible string in DT (no `realtek,rtd2171` or similar)
- The HDMI port probably routes through one of the DP controllers
- Need to identify the DP-to-HDMI bridge chip (check Windows driver INF, ACPI tables)
- Add bridge node to DTS (I2C or AUX bus device)

### Long-term: Full display pipeline
1. Fix PMIC glink device link to ps8830 (Type-C mux)
2. Get USB-C DP alt mode working via DP0
3. Add HDMI bridge to proper DP controller
4. Test with firmware loaded (adsp.mbn, cdsp.mbn)
