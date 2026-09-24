# Third-party notices

WinEXE original files are GPL-2.0-or-later (`LICENSE`, `COPYING`).
This document lists bundled or required third-party components.

WinEXE does **not** redistribute Microsoft Windows, Winamp, or game
binaries. Those remain the user’s responsibility.

## MiSTer FPGA framework (`fpga/sys/`)

Most files come from [MiSTer-devel](https://github.com/MiSTer-devel)
templates (sys_top, ascal, video mixer, OSD, and related modules).

Typical notices in-tree:

- GPL-2.0-or-later — e.g. `fpga/sys/sys_top.v` (Alexey Melnikov)
- GPL-3.0-or-later — e.g. `fpga/sys/hps_io.sv` (Till Harbaum / Alexey Melnikov)

Because GPL-2.0-or-later works may be conveyed under GPL-3, the
**combined FPGA core** should be treated as GPL-3.0-or-later
compatible. Preserve the per-file headers.

## Intel / Altera generated PLL sources

`fpga/rtl/pll*`, `fpga/sys/pll*`, and `fpga/sys/pll_cfg/*` include
Intel/Altera MegaWizard / PLL Reconfig output. Those files carry Intel
license text restricting use to Intel/Altera devices. They are the same
class of generated IP shipped by other MiSTer cores. Do not treat them
as original WinEXE code.

## Wine 7.1

Wine is [LGPL-2.1-or-later](https://wiki.winehq.org/Licensing).
WinEXE’s CI may extract WineHQ 7.1 i386 binaries for a prefix/runtime
artifact. That artifact is **not** in this git tree. If you
redistribute Wine binaries, include Wine’s license texts and offer
corresponding source as LGPL requires.

Default SuperStation path: `/media/fat/games/WinEXE/wine-installer/opt/wine-devel/`

## Box86

[Box86](https://github.com/ptitSeb/box86) is MIT.
The public zip ships the generic ARMHF binary from
[ryanfortner/box86-debs](https://github.com/ryanfortner/box86-debs)
(`box86-generic-arm`, see `Windows/box86-ss1/SOURCE.txt`).
Sidecar multimedia builds (`box86-gst`, `box86-gstflow`) are
experimental and are **not** in the v0.1.0-beta end-user zip.

## X.Org / dummy video / evdev

Relocatable ARMHF Xorg pieces are assembled from Debian packages
(typically MIT / X11 / X.Org licenses). See `docs/X11_RUNTIME.md`.
`dummy_drv.so` is extracted from `xserver-xorg-video-dummy`.

## Host libraries (fontconfig and deps)

`docs/HOST_LIBS.md` — Debian Bullseye armhf extracts. Individual
libraries keep their upstream licenses (typically MIT, BSD, or LGPL).

## Custom MiSTer Main (`MiSTer_WinEXE`)

Built from [Main_MiSTer](https://github.com/MiSTer-devel/Main_MiSTer)
plus the small WinEXE hook under `main/`. Main_MiSTer is GPL-3.0.
The compiled `MiSTer_WinEXE` binary is a CI artifact, not committed.

## Project-built helpers (not third-party applications)

These are original WinEXE helpers. They may be compiled by CI and
installed next to the launcher. They are **not** game or Windows files:

- `ss1-winexe-x11-present`
- `ss1-pal8-map.so`
- `ss1-civ2-cdaudio.so` (Civ II CD-audio ioctl shim)
- `ss1-cnc-pal8.dll` / `ss1-cnc-pal8.exe` (C&C PAL8 mailbox injector)

## What must never be justified by this file

Microsoft EXEs/DLLs, XP trees, WMP, Winamp, ISOs, BIN/CUE, ROMs,
music, AVI, or extracted game directories. Those are not licensed
by WinEXE.
