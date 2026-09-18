# WinEXE_Test FPGA core

Status: sources in `fpga/`. Quartus 17.0 compile is GitHub Actions
(`.github/workflows/build-winexe-core.yml`), not local. Colour-bar HDMI
and the Wine GUI path are **proven**. FPGA timing/video is frozen.

OSD application profiles and custom Main are ARM-side first:
[WINEXE_CORE.md](WINEXE_CORE.md). **Do not start Quartus until that
architecture is agreed.** The first OSD-enabled build only changes
`CONF_STR` (core name `WinEXE`, Application / Launch / Restart / Stop).
WMP is parked and is not an OSD item.


This core’s only job is a linear RGB framebuffer that the ARM side writes
and the FPGA/MiSTer scaler displays. Do not add DVD MPEG/YUV, DirectDraw
acceleration, or CRT options to the RBF.

## Current runtime (2026-09-17)

Proven on SuperStation One through this core: XP Notepad, XP Paint,
Winamp 2.91 (physical audio + MP3), original Win95 SimCity 2000, genuine
XP SP3 WMP9 UI, USB mouse/keyboard, OSD input recovery. SC2K uses a 30 Hz
presenter profile with skip-unchanged and 32×32 dirty spans; other apps
stay at 60 Hz. The SC2K tool palette is kept above the map by
`scripts/ss1-winexe-sc2k-toolbar.sh` (X restack only; no FPGA change).

WMP9 / DirectShow / GStreamer / WaveOut status (PCM physical audio
proven; DirectSound crackles; custom `ss1waveout.ax` is preferred):
[docs/WMP9_DSHOW.md](WMP9_DSHOW.md). Do not start C&C from this work.

```
Wine / winex11
    → Xorg 1.20.11 + xf86-video-dummy 640×480 RAM FB
       + evdev (event0 mouse, event1 keyboard, GrabDevice false)
    → ss1-winexe-x11-present (MIT-SHM + XFixes cursor; optional skip/dirty)
    → /dev/mem 0x30000000 BGRX stride 2560
    → WinEXE_Test.rbf ascal → HDMI
```

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
| **WinEXE FB A BGRX32** | **`0x30000000`** | 640×480×4 = 1 228 800 | **OK, no overlap** |
| **PAL8 pixels** | **`0x30200000`** | 640×480×1 = 307 200, stride 640 | was FB B; prototype uses this |
| **PAL8 palette** | **`0x3024B000`** | 256 × 32-bit `00RRGGBB` = 1024 | outside pixel range |
| PAL8 stats (ARM) | `0x3024C000` | 4 KB | not read by FPGA |
| pad | … `0x303FFFFF` | — | — |
| **mailbox** | **`0x30400000`** | 4 KB | magic `P8L8`, flags bit0 = PAL8 vs BGRX |

Same A/B/mailbox **base** the DVD player already mmap’d successfully on
this board. Spacing is 2 MB (DVD used that for 720×576×4 ≈ 1.6 MB; our
buffer is 1.2 MB, so it still fits). v1 uses **only buffer A**,
single-buffered. Tearing is acceptable for bars + Notepad proof.

ARM `DDRAM_ADDR` in the FPGA is `byte_addr[31:3]`, so
`0x30000000 >> 3 = 0x06000000` if we ever issue DDRAM reads ourselves.
v1 ascal does the BGRX pixel reads. The PAL8 prototype adds `pal8_fbctl`
which reads mailbox `0x30400000 >> 3 = 0x06080000` once per VBlank and,
on palette generation change, `0x3024B000 >> 3 = 0x06049600` (1 KB).

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

Colour-bar HDMI test **passed**. FPGA timing/video is frozen.

## GUI path (after bars)

Do **not** use `/dev/fb0`, `ss1-fb-present`, HPS n=1, or F9.

```
Wine / winex11
    → Xorg 1.20.11 + xf86-video-dummy 640×480 RAM FB
       + existing evdev (event0 mouse, event1 keyboard, GrabDevice false)
    → ss1-winexe-x11-present (MIT-SHM GetImage + XFixes cursor)
    → /dev/mem 0x30000000 BGRX stride 2560
    → WinEXE_Test.rbf ascal → HDMI
```

Xvfb was rejected because it has no native USB evdev path. Dummy keeps
the proven input stack and never opens MiSTer_fb.

Launcher (brings the stack up): `scripts/ss1-winexe-notepad.sh`
Next EXE on a live stack (Paint default): `scripts/ss1-winexe-run-exe.sh`
Presenter: GHA `.github/workflows/build-winexe-presenter.yml` (ARM only).
Winamp: `scripts/ss1-winexe-winamp.sh` (existing stack; stamps first-run/Gecko settings first).
SimCity 2000: `scripts/ss1-winexe-sc2k.sh` (registry stamp + 30 Hz dirty profile + toolbar watcher).
WMP9: `scripts/ss1-winexe-wmp9.sh` (box86-gstflow only; original Box86 untouched).
DirectShow PCM harness: `scripts/ss1-winexe-dshow.sh` (`ss1waveout.ax`, no WMP).

## Presenter profiles (ARM only)

`scripts/ss1-winexe-x11-present.c` / `ss1-winexe-present-restart.sh`.
HDMI and dummy X stay 60 Hz. Env:

| Variable | Default | Meaning |
|---|---|---|
| `SS1_HZ` | 60 | ARM present pace (SC2K uses 30) |
| `SS1_SKIP_UNCHANGED` | 1 | Skip uncached DDR memcpy when the composed frame matches the previous |
| `SS1_DIRTY` | 0 | SC2K: 1 — copy only coalesced dirty tiles |
| `SS1_TILE_W` / `SS1_TILE_H` | 32 / 32 | Dirty tile size |
| `SS1_DIRTY_PCT` | 60 | Full-frame fallback if dirty coverage ≥ this % |

Cursor movement counts as a change. Do not enable dirty globally; Winamp/Notepad/Paint keep `SS1_DIRTY=0`.

## SimCity 2000

Stage the original Win95 `WIN95/SC2K/` tree to `C:\SC2K\` (outside Program
Files so saves resolve). Do not commit the game. First launch needs the
installer registry from `WIN95/SETUP.INS`, stamped by
`ss1-winexe-sc2k-config.sh` + `ss1-winexe-sc2k.reg` (not sc2kfix, not
`SETUP.EXE`).

SC2K profile on launch:

- presenter 30 Hz, skip on, dirty 32×32
- `taskset` SIMCITY.EXE → CPU0, Xorg + presenter → CPU1
- Explorer `/desktop=ss1,640x480` (no-Explorer A/B failed: dummy X has no WM)
- `ss1-winexe-sc2k-toolbar.sh` restacks the 96×393 tool palette above the
  city map without activating it; menus/dialogs above the map are left alone

Switch apps with `ss1-winexe-stop-wine.sh` first (keeps FPGA, dummy X,
presenter, keep-input). Winamp/run-exe restore 60 Hz, dirty off, and
unpin presenter/Xorg (`taskset 0x3`).

## Winamp 2.91 first-run + mini-browser

Do **not** click the User information dialog each launch. Winamp 2.91
remembers that state here:

| Setting | File | Meaning |
|---|---|---|
| `[WinampReg] NeedReg=0` | `%windir%\winamp.ini` → `drive_c/windows/winamp.ini` | Skip **Winamp Setup: User information**. The exe reads this with `GetPrivateProfile` on `WinampReg` / `NeedReg` / `winamp.ini` (Windows directory, **not** Program Files). Missing key → show dialog. `noaod=1` in Program Files `Winamp.ini` is **not** this dialog (2.91 `winamp.exe` has no `noaod` string). |
| `[WinampReg] ID=…` | same file | Install id Winamp already wrote; keep it. |
| `mb_open=0` | `Program Files\Winamp\Winamp.ini` `[Winamp]` | Do not open the HTML mini-browser (`winampmb.htm` / ieframe). |
| `newverchk=0` / `newverchk2=0` | same | Disable version check / anonymous-stats nag. |
| Wine `AppDefaults\winamp.exe\DllOverrides` `mshtml`/`ieframe`/`shdocvw`=`disabled` plus launcher `WINEDLLOVERRIDES=…;mshtml=d;ieframe=d;shdocvw=d` | prefix `user.reg` + `ss1-winexe-winamp.sh` | Wine must not download/install **Gecko**. Do not install Gecko unless a later playback feature actually needs HTML. |

Stamp (wineserver stopped) then launch:

```
/media/fat/Windows/bin/ss1-winexe-winamp-config.sh
/media/fat/Windows/bin/ss1-winexe-winamp.sh
```

Bake the same `NeedReg=0` file and AppDefaults into the prebuilt WinEXE
Winamp prefix so a fresh unzip does not show the nags.

## Input ownership (USB vs MiSTer Main)

A loaded core leaves Main's `grabbed = 1`. Every OSD open **and close**
calls `user_io_osd_key_enable()` → `input_switch(-1)`, which does:

```
ioctl(fd, EVIOCGRAB, (grabbed | user_io_osd_is_visible()) ? 1 : 0);
```

in `Main_MiSTer/input.cpp` (`input_switch`, and the same ioctl when a
device is first opened). After OSD close, `osd_visible` is 0 but
`grabbed` is still 1, so event0/event1 are exclusive again and dummy
Xorg (fds still open, `GrabDevice false`) receives nothing.

Prototype workaround (no Main rebuild): `ss1-winexe-keep-input.sh watch`
gdb-`EVIOCGRAB 0` on **only** `/dev/input/event0` (Pixart) and
`event1` (SIGMA) while `/tmp/CORENAME` starts with `WinEXE`, skipping
that while `/tmp/OSD_VISIBLE` exists. Pico IR `event4`/`event5` stay
grabbed so OSD still has a controller.

### Long-term Main change (do this in Main_MiSTer, not the RBF)

When the running core name starts with `WinEXE` (or a future cfg flag
such as `linux_input=1`):

1. **Do not** `EVIOCGRAB` the Linux-owned USB mouse/keyboard while the
   OSD is hidden. Keep grabbing TinyUSB pico IR (and gamepads) as today.
2. On OSD **open**, grabbing those USB devices is allowed so the OSD can
   use them if no IR is present.
3. On OSD **close**, **do not** re-grab those USB devices; leave them to
   Linux/Xorg. Today `input_switch(-1)` re-applies grab because
   `grabbed` stays 1.
4. Do **not** call `input_switch(0)` for this — that path is tied to
   `video_fb_enable` / Linux n=0 HDMI, which steals the WinEXE scanout.

Concrete hooks:

- `input.cpp` `input_switch()` and the `ioctl(pool[n].fd, EVIOCGRAB, …)`
  at device-open time: skip (or force 0) for configured linux-handoff
  devices when `!user_io_osd_is_visible()`.
- Identify devices by the existing `idstr` / VID:PID (Pixart `093a:2510`,
  SIGMA `1c4f:008e`) or a `MiSTer.ini` list.
- `user_io_osd_key_enable()` can stay the OSD visibility toggle; only
  the grab predicate needs the WinEXE exception.

Until that lands, keep the userland watcher. It must not be a manual gdb
step after every OSD use.

## Files

- `fpga/` — DVD `sys/` + 27 MHz PLL, `WinEXE.sv` / `.qsf` / `.qpf` / `.qip`
- `.github/workflows/build-winexe-core.yml` — disk-free +
  `raetro/quartus:17.0` → `WinEXE_Test.rbf`
- `.github/workflows/build-winexe-presenter.yml` — Debian Bullseye armhf
  cross-build of `ss1-winexe-x11-present`
- `scripts/ss1-winexe-present.c` — ARM BGRX colour-bar writer
- `scripts/ss1-winexe-x11-present.c` — X dummy → `0x30000000` (60/30 Hz, skip, dirty)
- `scripts/ss1-winexe-present-restart.sh` — restart presenter only
- `scripts/ss1-winexe-xorg.sh` / `scripts/xorg.winexe.conf` — dummy 640×480 Xorg
- `scripts/ss1-mount-prefix.sh` — loop-mount `wineprefix-prebuilt.ext4`
- `scripts/ss1-winexe-stop-wine.sh` — comm-only Wine session cleanup
- `scripts/ss1-winexe-ungrab-input.sh` / `ss1-winexe-keep-input.sh` — USB vs Main
- `scripts/ss1-winexe-notepad.sh` — dummy Xorg + presenter + XP Notepad
- `scripts/ss1-winexe-run-exe.sh` — Paint (default) or any `apps/*.exe` on the live stack
- `scripts/ss1-winexe-winamp-config.sh` — `NeedReg=0` + `mb_open=0` + no Gecko
- `scripts/ss1-winexe-winamp.sh` — stamp + launch Winamp 2.91 on existing stack
- `scripts/ss1-winexe-sc2k-config.sh` / `ss1-winexe-sc2k.reg` — SETUP.INS registry
- `scripts/ss1-winexe-sc2k.sh` — SC2K 30 Hz + dirty + affinity + Explorer desktop
- `scripts/ss1-winexe-sc2k-toolbar.sh` — keep SC2K tool palette above the map
- `scripts/ss1-winexe-mem-wine.sh` — targeted Wine RSS/PSS snapshot
- `docs/WMP9_DSHOW.md` — WMP9 / DirectShow / GStreamer / WaveOut status
- `scripts/ss1-winexe-wmp9.sh` / `wmp9-install.sh` / `wmp9-config.sh` / `wmp9.reg` — genuine WMP9 (device-local XP files, not in git)
- `scripts/ss1-winexe-wine-gstflow.sh` — WMP-session Wine loader (`box86-gstflow`)
- `scripts/ss1-winexe-gst-env.sh` — private ARMHF GStreamer env
- `scripts/patch-box86-gst.py` / `patch-box86-gst-dataflow.py` — Box86 GStreamer class + dataflow bridges
- `scripts/ss1-gst-harness.c` / `ss1-gst-harness.sh` — i386 `filesrc → wavparse → fakesink` to EOS
- `scripts/ss1-winexe-dshow.c` / `ss1-winexe-dshow.sh` — PE32 DirectShow PCM harness
- `scripts/ss1-winexe-waveout.c` / `ss1-winexe-waveout.h` / `ss1waveout.def` — private WaveOut renderer
- `scripts/ss1-winexe-prefix-backup.sh` — snapshot the ext4 prefix image
- `scripts/ss1-winexe-cocreate.c` — CoCreate COM diagnostic

Parked HPS `/dev/fb0` helpers (not the live WinEXE path):
`scripts/ss1-xorg.sh`, `scripts/ss1-fb-present.sh`, `scripts/ss1-notepad.sh`,
`scripts/ss1-run-exe.sh`, `scripts/ss1-launch-notepad.sh`.

## Out of scope for the FPGA compile

DirectDraw acceleration, CRT, interlacing, scaler OSD, FPGA USB, n=1
HPS presenter, changing Box86/Wine. Application launchers and the ARM
presenter are software-only.
