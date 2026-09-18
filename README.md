# WinEXE

WinEXE is a shared **MiSTer / SuperStation** environment for running
selected 32-bit Windows programs through **Wine 7.1** and **Box86**,
with FPGA-backed **640×480** HDMI output.

One FPGA core, one generic launcher, per-application INI profiles, and
`.WEX` OSD entries. You supply legally obtained application files.

**Version:** v0.1.0-beta

This repository does **not** contain Microsoft Windows, game, or media
payloads.

## What it is

```
Wine 7.1 i386  →  Box86 (ARMv7 / Cortex-A9)
       ↓
dummy Xorg 640×480 (no /dev/fb0 scanout)
       ↓
ss1-winexe-x11-present  (BGRX, skip-unchanged, cursor-only DDR)
       ↓
FPGA DDR @ 0x30000000  →  WinEXE.rbf (ascal)  →  HDMI
```

Optional **PAL8** scanout (C&C) writes an 8-bit framebuffer and palette
mailbox. Desktop apps stay on the BGRX presenter.

A warm **READY** session keeps Xorg, the presenter, and input recovery
alive. Launching an application joins the existing 640×480 Wine desktop.
Stopping an application returns to READY instead of tearing the stack
down. A launch-memory floor (default 48000 kB `MemAvailable`) refuses a
start rather than risking a Linux OOM.

## Supported hardware

- SuperStation One / MiSTer-class DE10-Nano (ARMv7, ~512 MB HPS RAM)
- HDMI out from the WinEXE FPGA core
- USB keyboard and mouse (see [Input](#input))

## Quick install

No compiler on the device.

1. Copy or unzip **WinEXE-v0.1.0-beta.zip** onto the SD card (or clone
   this repo to a working directory).
2. On the SuperStation, install the ARM layout once:

   ```sh
   /path/to/WinEXE/install.sh /media/fat
   ```

3. Place companion runtime artifacts (from GitHub Actions, or a previous
   working SuperStation tree) under `/media/fat/Windows/`:

   | Artifact | Path |
   |---|---|
   | Wine 7.1 i386 | `wine-installer/opt/wine-devel/` |
   | Wine prefix (wineboot, no Microsoft apps) | `wineprefix-prebuilt/` (or `.ext4` loop) |
   | Box86 | `box86-ss1/box86` |
   | X11 runtime | `x11/` |
   | Host libs | `host-libs/` |
   | Presenter | `bin/ss1-winexe-x11-present` |
   | Dummy video driver | `x11/lib/xorg/modules/drivers/dummy_drv.so` |
   | PAL8 map (C&C) | `bin/ss1-pal8-map.so` |
   | Custom Main | `/media/fat/MiSTer_WinEXE` |

4. Copy **`WinEXE.rbf`** to `/media/fat/_Computer/WinEXE.rbf`
   (or `/media/fat/_Console/WinEXE.rbf`). That is the only public core
   name.
5. Append `mister/WinEXE.ini` to `/media/fat/MiSTer.ini` if `[WinEXE]`
   is missing (`main=MiSTer_WinEXE`).
6. Put legally owned application files in the directories listed in
   [docs/APPS.md](docs/APPS.md).
7. Load **WinEXE** from the MiSTer OSD, then **Load Application...** and
   pick a `.WEX`.

`install.sh` copies profiles, `.WEX` launchers, and the public launcher
scripts. It does not copy Wine, Box86, or any game EXE.

## Architecture

| Piece | Role |
|---|---|
| `WinEXE.rbf` | Shared FPGA core: 640×480 ascal, BGRX DDR, optional PAL8 |
| `ss1-winexe-launch.sh` | Generic launcher (boot / launch / stop / READY) |
| `profiles/*.ini` | Per-app paths, presenter flags, helpers |
| `games/WinEXE/*.wex` | OSD file-picker entries (`profile=...` only) |
| Wine 7.1 + Box86 | Frozen usermode stack |
| Dummy Xorg 640×480 | Off-screen desktop; not `/dev/fb0` |
| `ss1-winexe-x11-present` | BGRX presenter into FPGA DDR |
| `ss1-winexe-keep-input.sh` | Ungrab USB HID while the core is loaded |

Details: [docs/WINEXE_CORE.md](docs/WINEXE_CORE.md),
[docs/WINEXE_FPGA.md](docs/WINEXE_FPGA.md),
[docs/X11_RUNTIME.md](docs/X11_RUNTIME.md),
[docs/WINE_PREFIX.md](docs/WINE_PREFIX.md).

## HDMI / presenter

- The first frame after presenter start is always force-copied to DDR.
- Later frames skip unchanged tiles when enabled.
- Pointer motion updates a cursor rectangle instead of rewriting
  640×480×4 (~1.2 MB) every time.
- This is **not** a locked 60 fps guarantee. Some loads still miss
  16.67 ms. Further optimisation is future work.

## Memory

- Stopping an app cleans that Wine process (including leftover
  `mspmspsv.exe` from parked WMP sessions).
- READY services stay warm.
- `SS1_LAUNCH_MEM_FLOOR_KB` defaults to **48000**. Override the
  environment variable if you must; do not treat retuning as a
  supported beta feature.

## Input

Keep-input currently defaults to:

- mouse: `/dev/input/event0` (`SS1_MOUSE_EVENT`)
- keyboard: `/dev/input/event1` (`SS1_KBD_EVENT`)

Those numbers match the development SuperStation. They are **not** a
generic USB enumerator. If your devices land on other event nodes, set
the two variables before boot. Mouse-speed OSD is **not implemented**.

## Application policy

WinEXE ships profiles and helpers only. See [docs/APPS.md](docs/APPS.md)
for directories and filenames. Proven / parked status:
[docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

Do not add application binaries to this repository.

## Reconstruct companion runtimes

GitHub Actions (do not compile on the SuperStation):

- **Build WinEXE FPGA core** → `WinEXE.rbf`
- **Build WinEXE X11 presenter** → `ss1-winexe-x11-present`, `dummy_drv.so`
- **Build WinEXE FPGA core** (ARM jobs) → `ss1-pal8-map.so`, C&C PAL8 PE
- **Build MiSTer_WinEXE** → custom Main
- **Prepare Wine 7.1 win32 prefix** → `wineprefix-prebuilt.tar.xz`
- **Prepare ARMHF X11 runtime** / **host-libs** → tarballs

Box86 is the existing SuperStation tree; do not replace it casually.

## License

Original WinEXE files: **GPL-2.0-or-later**. Combined FPGA core includes
MiSTer files under GPL-2.0-or-later and GPL-3.0-or-later. Wine is LGPL;
Box86 is MIT. See [LICENSE](LICENSE), [COPYING](COPYING), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
