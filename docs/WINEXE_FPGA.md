# WinEXE_Test FPGA core

Status: sources in `fpga/`. Quartus 17.0 compile is GitHub Actions
(`.github/workflows/build-winexe-core.yml`), not local.

This core’s only job is a linear RGB framebuffer that the ARM side writes
and the FPGA/MiSTer scaler displays. DVD MPEG/YUV, Paint, DirectDraw,
audio, and CRT options are out of scope.

## Why not the parked Xorg/HPS path

When `WinEXE_Test.rbf` is loaded, the **core** owns HDMI. MiSTer Main’s
HPS planes (n=0 `/dev/fb0`, n=1 wallpaper) and `ss1-fb-present.sh` are
not the visible path.

## DVD pieces we reuse vs skip

From `/Users/jarvisaiassistant/Projects/dvd-core/fpga` (Quartus 17.0.2,
`raetro/quartus:17.0`, proven on this SuperStation):

Reuse:

- `sys/` (sys_top, ascal, hps_io, DDRAM/f2sdram, analog HDMI pipeline)
- `sys/sys.tcl` pinout / Cyclone V
- Build recipe: Docker Quartus 17.0, not Apple Silicon Quartus
- ARM `/dev/mem` into FPGA-visible DDR (same physical machine)

Do **not** copy:

- `fb_line_reader` YUV420 / BT.601 / 480i field weave
- `mycore` Rec.601 13.5 MHz interlaced raster
- DVD mailbox bits for ISO/interlace/16:9
- Dual ascal+CRT consumers of the same A/B buffers

DVD’s QSF comment is important: they **disabled** `MISTER_FB` because
HDMI ascal then became a second DDR reader of their A/B buffers while
the FPGA line-reader was already reading them for CRT. WinEXE has no
CRT line-reader in v1, so the scaler **should** be the DDR consumer.

## Chosen video path (v1)

```
ARM writes 640×480×32 BGRX at 0x30000000
        ↓  /dev/mem
DDR3 (outside Linux 511 MB)
        ↓  ascal (MISTER_FB=1)
MiSTer HDMI scaler → physical HDMI
```

Core outputs:

- `FB_EN = 1`
- `FB_WIDTH = 640`, `FB_HEIGHT = 480`
- `FB_FORMAT = 32bpp BGR` (`110` plus bit4 BGR = `0b10110`)
- `FB_STRIDE = 2560` (640×4)
- `FB_BASE = 0x30000000`
- `VIDEO_ARX/ARY = 4:3`
- Dummy/black `VGA_*` so analog VGA is inert (`VGA_DISABLE` if needed)
- `VGA_F1 = 0`, `HDMI_BOB_DEINT = 0` (progressive)
- Minimal OSD: Reset only (`CONF_STR = "WinEXE_Test;;"`)

HDMI **connector** timing stays whatever `MiSTer.ini` `video_mode` already
is (on this SS1: mode 8 = 1920×1080@60). ascal scales the 640×480 FB into
that. No OSD scale controls in v1.

Fallback if `MISTER_FB` HDMI is blank on hardware: 640×480p60 `VGA_*`
raster + a **RGB-only** DDRAM line reader (DVD’s proven DDRAM port,
without YUV). That is a second compile, not the first.

## DDR addresses (verified on the live SS1)

Kernel: `mem=511M memmap=513M$511M`

`/proc/iomem` System RAM: `00000000-1fefffff` (511 MB).

| Region | Address | Size | vs System RAM |
|---|---|---|---|
| Linux | `0x00000000`–`0x1FEFFFFF` | 511 MB | — |
| HPS `MiSTer_fb` n=0/1/2 | `0x22000000` | ~24 MB | **outside** RAM (parked path) |
| **WinEXE FB A** | **`0x30000000`** | 640×480×4 = 1 228 800 | **OK, no overlap** |
| WinEXE FB B (reserved) | `0x30200000` | same | OK (unused in v1) |
| mailbox (reserved) | `0x30400000` | 4 KB | OK (unused in v1) |

Same A/B/mailbox **base** the DVD player already mmap’d successfully on
this board. Spacing is 2 MB (DVD used that for 720×576×4 ≈ 1.6 MB; our
buffer is 1.2 MB, so it still fits). v1 uses **only buffer A**,
single-buffered. Tearing is acceptable for bars + Notepad proof.

ARM `DDRAM_ADDR` in the FPGA is `byte_addr[31:3]`, so
`0x30000000 >> 3 = 0x06000000` if we ever issue DDRAM reads ourselves.
v1 does not; ascal does.

## How ARM writes

Small native ARMv7 binary, cross-compiled (Docker/GHA
`arm-linux-gnueabihf-gcc`), installed as
`/media/fat/Windows/bin/ss1-winexe-present`.

v1 `pattern` mode:

1. `open("/dev/mem", O_RDWR|O_SYNC)`
2. `mmap` 1 228 800 bytes at `0x30000000`
3. Fill a 640×480 packed BGRX checkerboard / colour bars
4. Leave the mapping; optionally rewrite every ~1 s so we can see it is live

No Python 1920×1080 presenter. One full-frame store is enough.

Wine is **not** in the first physical test.

## How FPGA/ascal reads

With `MISTER_FB=1`, `sys_top` does `FB_EN <= LFB_EN | fb_en`. While this
core is loaded, Main should not assert Linux `LFB_EN` (that is the F9/HPS
path). The core’s `fb_en` wins, `FB_BASE` is `0x30000000`, ascal DMA-reads
that linear buffer and drives HDMI.

Main is out of Windows framebuffer ownership for as long as this RBF is
the running core. F12 still opens the MiSTer OSD on top, which is desired.

## Expected timing

| Item | Value |
|---|---|
| Framebuffer | 640×480 progressive, 32-bit BGRX, stride 2560 |
| Core pixel rate | not generated in v1 (ascal is the HDMI master) |
| HDMI | SS1 `video_mode=8` → 1920×1080@60, 4:3 content letterboxed |
| Refresh of ARM writes | software loop; not vsync-locked in v1 |

## First physical test (before Wine)

1. Build `WinEXE_Test.rbf` (Quartus 17.0 Docker — **not started**).
2. Copy to `/media/fat/WinEXE_Test.rbf`.
3. Load it from the MiSTer menu (MENU disappears; core owns HDMI).
4. SSH: run `ss1-winexe-present pattern`.
5. Pass: stable HDMI sync + obvious colour bars/checkerboard.
6. Fail: no sync, or bars missing → do not involve Wine; consider the
   VGA+DDRAM fallback compile.

Only after bars work:

- Keep USB mouse/keyboard on Linux evdev (unchanged).
- Point Xorg at a **private** 640×480 buffer if `/dev/fb0` would reintroduce
  ShadowFB corruption; v1 may simply `memcpy` a 640×480 crop or a dummy
  pixmap. Not designed in detail until bars pass.
- Launch `/media/fat/Windows/apps/notepad.exe` via existing `ss1-run-exe.sh`.

## Files

- `fpga/` — DVD `sys/` + 27 MHz PLL, `WinEXE.sv` / `.qsf` / `.qpf` / `.qip`
- `.github/workflows/build-winexe-core.yml` — disk-free +
  `raetro/quartus:17.0` → `WinEXE_Test.rbf`
- `scripts/ss1-winexe-present.c` — ARM BGRX pattern writer

## Out of scope for this compile

Paint, Winamp, DirectDraw, audio, CRT, interlacing, scaler OSD, FPGA USB,
n=1 presenter, changing Box86/Wine.
