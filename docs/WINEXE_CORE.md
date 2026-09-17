# WinEXE core — Phase 1 architecture

WMP is **parked**. Do not continue WMP memory/audio work. C&C is the first
new profile (index 4) and a DirectDraw probe only — do not add PAL8/RGB565
or FPGA video changes until that probe has evidence.
This document is the Phase 1 deliverable: ARM/Main/profile design **before**
any Quartus build.

One shared `WinEXE.rbf`. Application differences live in INI profiles and
one launcher. OSD uses stock MiSTer `CONF_STR` / `status[]` / `user_io`.

**Do not start the ~10–15 minute GitHub Actions FPGA job until this layout
is agreed.** FPGA sources in `fpga/WinEXE.sv` are unchanged in this phase.

## 1. Profile schema

Files: `/media/fat/Windows/profiles/<id>.ini` (repo: `profiles/`).

```
[osd]
index=0          # OSD value; live RBF is O[2:1] (0–3). Index 4 needs O[3:1].
menu=1           # 1 = OSD list, 0 = parked/SSH only
experimental=0
parked=0

[app]
name=Notepad
exe=...                  # Wine path or Unix path
unix_exe=...             # optional existence check
workdir=...
args=
explorer=1
desktop=ss1,640x480
require=                 # fail launch if missing
optional=                # warn only (Paint MFC42u.dll)

[runtime]
box86=                   # empty = default Wine/Box86
wine_prefix=/media/fat/Windows/wineprefix-prebuilt

[env]
KEY=value                # exported before Wine

[display]
presenter_hz=60
skip_unchanged=1
dirty=0
tile_w=32
tile_h=32
dirty_pct=60             # full-frame fallback %
fb_format=auto           # auto|bgrx32|rgb565|pal8
xsetroot=#000000         # idle is black; Notepad/Paint keep navy

[cpu]
app_affinity=            # taskset mask once app_comm appears
presenter_affinity=
xorg_affinity=
app_comm=                # /proc/pid/comm, e.g. SIMCITY.EXE

[helpers]
pre=                     # ;-separated, wineserver stopped
post=
background=              # e.g. toolbar watcher
cleanup=

[config]
registry=                # documentation / stamp input
script=                  # used if helpers.pre is empty
```

`fb_format` is reserved. The presenter still writes 640×480 BGRX at
`0x30000000`. Do not implement RGB565/PAL8 yet.

The launcher has **no** SC2K or Winamp `if` branches. Proven fixes are INI:

| App | Profile | Encoded behaviour |
|---|---|---|
| Notepad | `notepad.ini` | XP `apps/notepad.exe`, 60 Hz, dirty off, navy root |
| Paint | `paint.ini` | XP `mspaint.exe`, optional `MFC42u.dll`, 60 Hz |
| Winamp 2.91 | `winamp2.ini` | `winamp-config.sh` (`NeedReg=0`, `mb_open=0`, `out_wave.dll`, Gecko off), 60 Hz |
| SimCity 2000 | `sc2k.ini` | 30 Hz, skip, dirty 32×32, `dirty_pct=60`, SIMCITY CPU0 (`0x1`), presenter/Xorg CPU1 (`0x2`), `sc2k-config.sh` + toolbar watcher |
| Command & Conquer | `cnc.ini` | Win95 `C&C95.EXE`, 60 Hz BGRX, `+ddraw` log probe, OSD 4 (RBF still 0–3) |
| WMP9 | `experimental/wmp9.ini` | `menu=0`, parked |

OSD launch does not auto-play a Winamp track. The SSH wrapper still may.

## 2. Directory structure

Target on the SD card:

```
/media/fat/_Computer/WinEXE.rbf     # preferred menu folder
/media/fat/_Console/WinEXE.rbf      # also valid; name matters more than folder
/media/fat/games/WinEXE/*.wex       # Load Application... picker
/media/fat/MiSTer.ini               # [WinEXE] / [WinEXE_Test] main=MiSTer_WinEXE
/media/fat/MiSTer_WinEXE            # custom Main
/media/fat/Windows/
  bin/          launchers, presenter, wine wrappers
  profiles/     INI files from this repo
  helpers/      optional extra helper scripts
  runtime/      private GStreamer etc. (already used by parked WMP)
  apps/         user-supplied PE32 (not in git)
  logs/
  wineprefix-prebuilt/   existing prefix (not moved this phase)
  box86-ss1/             existing Box86 trees (not moved)
  x11/ host-libs/        existing (not moved)
```

Today’s `WinEXE_Test.rbf` at `/media/fat/` stays until the first OSD RBF
is installed. Copyrighted EXEs stay out of git (`apps/README.md`).

## 3. OSD menu

File-based launcher (no fixed application list):

```
localparam CONF_STR = {
	"WinEXE;;",
	"-;",
	"F0,WEX,Load Application...;",
	"-;",
	"T[5],Restart;",
	"T[6],Stop;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"V,v",`BUILD_DATE
};
```

On-screen:

```
WinEXE
----------------
Load Application... *.WEX
Restart
Stop
----------------
Reset
Reset and close OSD
```

`.WEX` files live in `/media/fat/games/WinEXE/` (stock `HomeDir()`).
Main intercepts the selection in `user_io_file_tx` and does **not** send
the file to the FPGA. Adding an application is a new INI + `.WEX`; no
Quartus, no Main rebuild.

## 4. Status-bit mapping

Current `fpga/WinEXE.sv` uses **only** `T[0]` / `R[0]` (bit 0). Bits 1–127
are free. Do not reuse bit 0.

| Bits | CONF_STR | Role | Kind |
|---|---|---|---|
| `[0]` | `T[0]` / `R[0]` | Soft Reset (reserved) | trigger / reset+close |
| `[2:1]` | `O[2:1]` | Application 0..3 | latched option |
| `[3]` | — | spare (8-app nibble later) | unused |
| `[4]` | `T[4]` | Launch | momentary pulse |
| `[5]` | `T[5]` | Restart | momentary pulse |
| `[6]` | `T[6]` | Stop | momentary pulse |
| `[7]` | — | spare | unused |

Index: 0 Notepad, 1 Paint, 2 Winamp 2, 3 SimCity 2000.

Leaving `[3]` free means a later `O[3:1]` (8 apps) does not shift Launch.

## 5. How custom Main detects Launch / Stop / Restart

MiSTer Main already owns `cur_status[]`. `user_io_poll()` calls
`check_status_change()` (`UIO_GET_STATUS`) for 8-bit cores, then other
core polls.

Menu.cpp already pulses T/R as `user_io_status_set(opt, 1)` then
`user_io_status_set(opt, 0)` in the same handler, so a later poll of
`cur_status` never sees Launch. WinEXE-specific Main hooks the rising
call inside `user_io_status_set()` via `winexe_status_event()`. It does
**not** clear T bits.

1. `opt` start bit 4, value 1 → Launch `ss1-winexe-launch.sh osd <O[2:1]>`
2. start bit 5, value 1 → Restart
3. start bit 6, value 1 → Stop / idle

`T[n]` is still the stock trigger. This is not a new mailbox.

`O[2:1]` is **not** an action. Changing Application in the OSD only
updates latched bits. Wine starts on **Launch** (or Restart).

## 6. How app selection reaches the ARM launcher

```
OSD Application  →  status[2:1]
OSD Launch       →  status[4] pulse (menu set 1 then 0)
        ↓
MiSTer_WinEXE winexe_status_event()
        ↓
ss1-winexe-launch.sh osd <0-3>
        ↓
profiles/*.ini with matching [osd] index
        ↓
stop previous app → apply env/presenter/CPU/helpers → wine <exe>
```

SSH without OSD:

```
ss1-winexe-launch.sh launch notepad|paint|winamp2|sc2k
ss1-winexe-launch.sh restart|stop|status
```

Existing wrappers (`ss1-winexe-notepad.sh`, …) exec the generic launcher.

## 7. Input ownership

Today: `input.cpp` `grabbed = 1` for any loaded core.
`EVIOCGRAB` uses `(grabbed | user_io_osd_is_visible())`. OSD close
calls `input_switch(-1)` and **re-grabs** USB. Prototype
`ss1-winexe-keep-input.sh` gdb-ungrabs `event0`/`event1` unless
`/tmp/OSD_VISIBLE`. Pico IR stays grabbed so OSD still opens.

**Eventual** WinEXE behaviour:

| | USB keyboard/mouse | Pico IR / OSD pads |
|---|---|---|
| OSD closed | Linux/Xorg | Main keeps grab (OSD can open) |
| OSD open | Main | Main |

`input_switch(0)` is **not** sufficient: it ungrabs Pico too. Phase 1
does **not** change Main input. Keep the watcher. Later: a WinEXE
device-class filter on the two `EVIOCGRAB` sites
(`input.cpp` ~5523, `input_switch` ~6456). Low-risk only after that
filter exists.

Idle (no Xorg): watcher stopped; stock grab is correct for OSD-only.

## 8. Implemented without FPGA changes

| Item | Path |
|---|---|
| Schema + 4 OSD profiles | `profiles/*.ini` |
| Parked WMP profile | `profiles/experimental/wmp9.ini` |
| Generic launcher | `scripts/ss1-winexe-launch.sh` |
| Idle FB blank | `scripts/ss1-winexe-blank.sh` |
| Layout installer | `scripts/ss1-winexe-install-layout.sh` |
| Wrappers → launcher | notepad / paint / winamp / sc2k / run-exe |
| Main hook (source only) | `main/support/winexe/*`, `main/PATCHES.md` |
| Core INI fragment (merge into MiSTer.ini) | `mister/WinEXE.ini` |
| Helpers dir | `helpers/README.md` |

Not built this phase: Quartus RBF, `MiSTer_WinEXE` binary, CONF_STR edit.

SSH test on the current `WinEXE_Test.rbf`:

```
ss1-winexe-install-layout.sh /media/fat
ss1-winexe-launch.sh launch notepad
ss1-winexe-launch.sh launch sc2k
ss1-winexe-launch.sh stop
```

OSD Launch cannot work until the first CONF_STR rebuild.

## 9. FPGA changes for the first OSD-enabled RBF

**Warn before starting the GHA Quartus job (~10–15 minutes).** One remote
build after this architecture is agreed. Do not produce per-app RBFs.

Edit **only** `fpga/WinEXE.sv` `CONF_STR` (and the status-bit comment):

1. Rename `"WinEXE_Test;;"` → `"WinEXE;;"` so `/tmp/CORENAME` and the
   `[WinEXE]` section in `MiSTer.ini` match.
2. Insert the Status Bit Map comment in §3.
3. Add `O[2:1]`, `T[4]`, `T[5]`, `T[6]` as in §3.
4. Keep `T[0]` / `R[0]` Reset.
5. Do **not** wire `status[]` into video/audio RTL. Launch is ARM-side.
6. Keep VGA RGB = 0 (black) and `MISTER_FB` 640×480 BGRX at `0x30000000`.
7. Ship `WinEXE.rbf` (GHA already uploads `WinEXE.rbf` and `WinEXE_Test.rbf`).
8. Install under `/media/fat/_Computer/` (or `_Console/`). Keep the old
   `WinEXE_Test.rbf` until the new core is proven.

Optional later (not this RBF): FB format bits for RGB565/PAL8.

## Idle state

After `Stop` / core load (`winexe_init` → `idle`):

- FPGA core stays loaded
- Wine gone (`ss1-winexe-stop-wine.sh`)
- Helpers gone
- Xorg + presenter stopped
- framebuffer zeroed (`ss1-winexe-blank.sh`)
- keep-input watcher stopped
- OSD still works (Main owns USB)
- RAM back near the pre-Wine ~440 MB available class

`Launch` brings Xorg + presenter + profile runtime back.

## Custom Main vs upstream

See `main/PATCHES.md`. Mechanism is stock `main=` in `user_io_init()`.
Delta: `is_winexe()`, `winexe_init()`, `winexe_status_event()` from
`user_io_status_set`. Makefile already wildcards `support/*/*.cpp`.
No new UIO command.

## Parked WMP (kept, not in OSD)

Keep Box86 GStreamer patches, `box86-gstflow`, GStreamer runtime,
DirectShow harness, `ss1waveout.ax`, `docs/WMP9_DSHOW.md`, all
`ss1-winexe-wmp*` scripts. SSH: `ss1-winexe-wmp9.sh` or
`ss1-winexe-launch.sh launch wmp9`. Best WaveOut config remains 12×30 ms,
prime 9. Next WMP blocker is process memory, not the renderer.
