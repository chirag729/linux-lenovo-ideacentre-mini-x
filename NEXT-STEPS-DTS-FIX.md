# Next Steps: DTS Fix for Display (2026-02-18)

## Problem

Boot 7 proved DRM_MSM probes successfully, but the DRM card is never created because
the component aggregate can't bind. The DPU expects 3 display components but only 1
registers:

```
aggregate: ae01000.display-controller       -> not bound
  ae90000.displayport-controller            -> registered, not bound
  (unknown)                                 -> not registered  (DP1/aea0000)
  (unknown)                                 -> not registered  (port@6 target?)
```

**Root cause:** DP1 (aea0000, eDP) has an eDP panel child in the DT. On a desktop
with no built-in panel, the panel probe fails and DP1 never calls `component_add()`.

## Fix: Edit the Board DTS

### Option A: Quick iteration on Pi (decompile/edit/recompile DTB)

1. Mount the USB on the Pi: `sudo mount /dev/sda1 /mnt`
2. Decompile the DTB:
   ```bash
   dtc -I dtb -O dts -o /tmp/board.dts /mnt/dtb/x1p42100-lenovo-ideacentre-x-gen10.dtb
   ```
3. Edit `/tmp/board.dts`:
   - Find the `displayport-controller@aea0000` node
   - Change its `status` from `"okay"` to `"disabled"`
   - OR: delete the `port@5` endpoint from the `display-controller@ae01000/ports/` node
4. Recompile:
   ```bash
   dtc -I dts -O dtb -o /mnt/dtb/x1p42100-lenovo-ideacentre-x-gen10.dtb /tmp/board.dts
   ```
5. `sudo sync && sudo umount /mnt`
6. Boot with option 3 (DRM enabled)

**Advantage:** Fast, no kernel rebuild needed.
**Disadvantage:** Decompiled DTS uses phandle numbers, hard to read. Not upstreamable.

### Option B: Proper fix on WSL2 (edit source DTS)

1. On WSL2, edit `~/kernel/misaleh-linux/arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-x-gen10.dts`
2. Add/modify:
   ```dts
   /* Disable eDP -- no built-in panel on desktop */
   &mdss_dp1 {
       status = "disabled";
   };
   ```
   Or if the board DTS already has `&mdss_dp1 { status = "okay"; }`, change it to disabled.
3. Rebuild just the DTB (seconds):
   ```bash
   cd ~/kernel/misaleh-linux
   make dtbs
   ```
4. Copy new DTB to USB:
   ```bash
   cp arch/arm64/boot/dts/qcom/x1p42100-lenovo-ideacentre-x-gen10.dtb /mnt/c/path/to/usb/dtb/
   ```
5. Boot with option 3

**Advantage:** Clean, upstreamable fix.
**Disadvantage:** Requires WSL2 session.

## What Should Happen After the Fix

With DP1 disabled, the component aggregate should only expect DP0 (ae90000).
Since DP0 already registers as a component, `msm_drm_bind()` should fire:

1. DRM card created (`/sys/class/drm/card0`, `/dev/dri/card0`)
2. DP0 connector registered (USB-C DisplayPort)
3. DPU/CRTC initialized
4. **But:** HDMI still won't work yet -- needs bridge chip identification

## HDMI Bridge -- Still Unknown

The HDMI port needs a DP-to-HDMI bridge chip described in the DTS. Based on Codex
review of X1P42100 ThinkBook 16 patches, the bridge is likely **Realtek RTD2171**.

To confirm, check on Lenovo Windows:
```powershell
# Check for Realtek display bridge in Device Manager
Get-PnpDevice | Where-Object { $_.FriendlyName -match "RTD|Realtek.*bridge|HDMI" }

# Check ACPI tables for bridge references
# Look in hardware/acpi-tables/ if extracted

# Check Qualcomm display driver INF for bridge references
Get-ChildItem "C:\Windows\INF\oem*.inf" | Select-String -Pattern "RTD2171|bridge|HDMI"
```

Once identified, add to the DTS under the correct DP controller:
```dts
&mdss_dp0 {  /* or whichever DP drives HDMI */
    status = "okay";

    aux-bus {
        hdmi-bridge@... {
            compatible = "realtek,rtd2171";
            /* reg, power-supply, enable-gpios, etc. */
        };
    };
};
```

## SSH Fix -- Still Needed

Boot 7 initramfs v5 (fakeroot-built, root:root) still rejects SSH passwords.
Dropbear says "Bad password attempt" -- the password hash might not match.

To debug on next boot:
```bash
# Via telnet, check the shadow file
cat /etc/shadow
# Check /root ownership
ls -la / | grep root
# Try setting password at runtime
echo "root:linux" | chpasswd
# Then test SSH from Pi
```

Or switch to key-based auth:
```bash
# Generate a key on Pi if not done
ssh-keygen -t ed25519 -f ~/.ssh/lenovo_key -N ""
# Add to initramfs /root/.ssh/authorized_keys
```

## Summary of All Boot Options

| Option | Cmdline | Purpose |
|--------|---------|---------|
| 1 | ACPI, nomodeset | No DTB, display test |
| 2 | DTB, DRM disabled | **Safe fallback**, telnet works |
| 3 | DTB, DRM enabled, drm.debug | **Display testing** |
| 4 | DTB, DRM enabled, nomodeset | DRM probes but no modeset |
