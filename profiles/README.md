# WinEXE application profiles

INI files consumed by `ss1-winexe-launch`. One shared `WinEXE.rbf`;
these files are the per-app differences.

Install as `/media/fat/Windows/profiles/`.

OSD selection uses `.WEX` pointers in `/media/fat/games/WinEXE/`.
Do **not** duplicate INI settings in the `.WEX`.

Do **not** put copyrighted EXEs here. Profiles only describe
user-supplied paths. See [docs/APPS.md](../docs/APPS.md).

## OSD applications

| `.WEX` | Profile | Status |
|---|---|---|
| `Notepad.wex` | `notepad.ini` | Working |
| `Paint.wex` | `paint.ini` | Working |
| `Winamp 2.wex` | `winamp2.ini` | Working (UI / playback-state) |
| `SimCity 2000.wex` | `sc2k.ini` | Working |
| `Command & Conquer.wex` | `cnc.ini` | Playable; performance still in progress |
| `Minesweeper.wex` | `minesweeper.ini` | Working |
| `Solitaire.wex` | `solitaire.ini` | Working |
| `FreeCell.wex` | `freecell.ini` | Working |
| `Hearts.wex` | `hearts.ini` | Minor: Pass Left |
| `Civilization II.wex` | `civ2.ini` | Working gameplay/music; advisor video unfinished |

`experimental/wmp9.ini` is parked (`menu=0`). Filename is historical;
the parked player is WMP 7.1.

## Schema

See [docs/WINEXE_CORE.md](../docs/WINEXE_CORE.md). `fb_format` accepts
`auto`, `bgrx32`, `rgb565`, `pal8`. Desktop apps use BGRX. C&C may use
the existing PAL8 path.
