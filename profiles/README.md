# WinEXE application profiles

Human-readable INI files consumed by `ss1-winexe-launch`. One shared
`WinEXE.rbf`; these files are the per-app differences.

Install on the SuperStation as `/media/fat/Windows/profiles/`.

OSD selection uses `.WEX` pointers in `/media/fat/games/WinEXE/`
(`wex/*.wex` in this repo). Do **not** duplicate INI settings in the
`.WEX`.

Do **not** put copyrighted EXEs here. Profiles only describe expected
user-supplied paths.

## Working applications

| `.WEX` | Profile | Application |
|---|---|---|
| `Notepad.wex` | `notepad.ini` | XP Notepad |
| `Paint.wex` | `paint.ini` | XP Paint |
| `Winamp 2.wex` | `winamp2.ini` | Winamp 2.91 |
| `SimCity 2000.wex` | `sc2k.ini` | SimCity 2000 |
| `Command & Conquer.wex` | `cnc.ini` | Command & Conquer Gold (stock C&C95.EXE) |

Game data and `CnC_NOD95.iso` stay on the SuperStation, not in git.
DirectDraw GetCaps findings (SYSTEMMEMORY vs video buffer):
[docs/CNC_DDRAW.md](../docs/CNC_DDRAW.md). `experimental/wmp9.ini` is
parked (`menu=0`).

SSH:

```
ss1-winexe-launch.sh launch-wex /media/fat/games/WinEXE/Notepad.wex
ss1-winexe-launch.sh launch notepad
ss1-winexe-launch.sh restart
ss1-winexe-launch.sh stop
```

## Schema

See [docs/WINEXE_CORE.md](../docs/WINEXE_CORE.md) for the full key list.
`fb_format` accepts `auto`, `bgrx32`, `rgb565`, `pal8`. Only `auto` /
`bgrx32` are implemented (today’s 640×480 BGRX presenter).
