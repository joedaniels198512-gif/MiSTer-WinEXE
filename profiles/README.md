# WinEXE application profiles

Human-readable INI files consumed by `ss1-winexe-launch`. One shared
`WinEXE.rbf`; these files are the per-app differences.

Install on the SuperStation as `/media/fat/Windows/profiles/`.

Do **not** put copyrighted EXEs here. Profiles only describe expected
user-supplied paths.

## OSD list (menu=1)

| OSD index | File | Application |
|---|---|---|
| 0 | `notepad.ini` | XP Notepad |
| 1 | `paint.ini` | XP Paint |
| 2 | `winamp2.ini` | Winamp 2.91 |
| 3 | `sc2k.ini` | SimCity 2000 |

`experimental/wmp9.ini` is parked (`menu=0`). SSH only.

## Schema

See [docs/WINEXE_CORE.md](../docs/WINEXE_CORE.md) for the full key list.
`fb_format` accepts `auto`, `bgrx32`, `rgb565`, `pal8`. Only `auto` /
`bgrx32` are implemented (today’s 640×480 BGRX presenter).
