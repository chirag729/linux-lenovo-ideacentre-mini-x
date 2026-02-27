# Session Summary: 2026-02-27

## Major Breakthrough: Display Working!

**Boot 28** achieved working HDMI display output via efifb (UEFI framebuffer preservation).

### The Problem
- Display worked during UEFI/GRUB but went blank when Linux booted
- efifb probed successfully but framebuffer writes weren't reaching the display
- Display clocks showed `enable_count=0` - they were being disabled by the kernel

### Root Cause Analysis
Both Codex and Gemini confirmed:
1. `clk_ignore_unused` kernel parameter only prevents late-init clock disable
2. It does NOT protect clocks if no driver claims them
3. MDSS disabled in DTS meant no driver was holding display clocks
4. The clocks needed a "dummy consumer" to keep them enabled

### The Fix
Added `CLK_IS_CRITICAL` flag to key display clocks in `dispcc-x1e80100.c`:
- `disp_cc_mdss_mdp_clk` - MDP (display processor) clock
- `disp_cc_mdss_ahb_clk` - AHB bus clock
- `disp_cc_mdss_vsync_clk` - vsync clock

Combined with:
- `ALWAYS_ON` flag on `mdss_gdsc` (from Boot 27)
- `nomodeset video=efifb:on clk_ignore_unused pd_ignore_unused regulator_ignore_unused` cmdline
- MDSS disabled in DTS to prevent DPU driver from resetting hardware

### Files Modified This Session
1. `drivers/clk/qcom/dispcc-x1e80100.c`:
   - Line ~805: Added `CLK_IS_CRITICAL` to `disp_cc_mdss_ahb_clk`
   - Line ~1349: Added `CLK_IS_CRITICAL` to `disp_cc_mdss_mdp_clk`
   - Line ~1515: Added `CLK_IS_CRITICAL` to `disp_cc_mdss_vsync_clk`
   - Line ~1522: Added `ALWAYS_ON` to `mdss_gdsc` (earlier in session)

2. `/mnt/usb/EFI/BOOT/grub.cfg`:
   - Added `regulator_ignore_unused` to option 1 cmdline

### Boot 28 Verification
```
$ cat /sys/kernel/debug/clk/clk_summary | grep -E "disp_cc_mdss_(mdp_clk|ahb_clk|vsync_clk)"
disp_cc_mdss_mdp_clk    1       1        0        325000000
disp_cc_mdss_vsync_clk  1       1        0        19200000
disp_cc_mdss_ahb_clk    1       1        0        19200000
```
The `1` in the enable_count column (first column after name) confirms clocks are held enabled.

### What Works Now
- Tux logo visible on HDMI display
- Console text visible (fbcon working)
- SSH access via Ethernet
- ADSP/CDSP firmware loaded

### Next Steps for Full DRM Support
1. Identify bridge chip (ITE IT66311/IT66312 at I2C 3:0x5b) - may need driver
2. Get HPD working (GPIO 120 reads LOW even with cable connected)
3. Re-enable MDSS/DPU for proper hardware-accelerated graphics
4. Write proper driver for bridge chip if needed

### Boot Logs
- Saved to: `testing/boot-logs/20260227-boot28-clk-is-critical-success/`
