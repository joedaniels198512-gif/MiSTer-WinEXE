# User application directories

Place files you are legally allowed to use on the SuperStation.
This project does not link to downloads and does not ship these files.

## Layout

```
/media/fat/
  WinEXE.ini                 # fragment; also merged into MiSTer.ini
  MiSTer.ini                 # must contain [WinEXE] main=MiSTer_WinEXE
  MiSTer_WinEXE              # custom Main (Actions artifact)
  _Computer/WinEXE.rbf       # public FPGA core name
  games/WinEXE/*.wex         # OSD picker
  Windows/
    bin/                     # launcher, presenter, helpers
    profiles/                # INI profiles from this repo
    apps/                    # YOUR PE32 files
    logs/
    wineprefix-prebuilt/     # Wine prefix (no Microsoft apps in git)
    wine-installer/          # Wine 7.1
    box86-ss1/               # Box86
    x11/                     # dummy Xorg runtime
    host-libs/
```

## Profiles

### Notepad — `notepad.ini` / `Notepad.wex`

| | |
|---|---|
| Directory | `/media/fat/Windows/apps/` |
| Executable | `notepad.exe` (XP SP3 PE32) |
| Sidecars | none |
| CD/image | no |

### Paint — `paint.ini` / `Paint.wex`

| | |
|---|---|
| Directory | `/media/fat/Windows/apps/` |
| Executable | `mspaint.exe` |
| Sidecars | `MFC42u.dll` from the same XP ISO if Paint asks |
| CD/image | no |

### Minesweeper — `minesweeper.ini` / `Minesweeper.wex`

| | |
|---|---|
| Directory | `/media/fat/Windows/apps/xp-games/` |
| Executable | `winmine.exe` |
| Sidecars | none required |
| CD/image | no |

### Solitaire — `solitaire.ini` / `Solitaire.wex`

| | |
|---|---|
| Directory | `/media/fat/Windows/apps/xp-games/` |
| Executable | `sol.exe` |
| Sidecars | `cards.dll` (set `cards=n` in the profile) |
| CD/image | no |

### FreeCell — `freecell.ini` / `FreeCell.wex`

| | |
|---|---|
| Directory | `/media/fat/Windows/apps/xp-games/` |
| Executable | `freecell.exe` |
| Sidecars | `cards.dll` |
| CD/image | no |
| Notes | Helper sends F2 after the window maps so a deal starts |

### Hearts — `hearts.ini` / `Hearts.wex`

| | |
|---|---|
| Directory | `/media/fat/Windows/apps/xp-games/` |
| Executable | `mshearts.exe` |
| Sidecars | `cards.dll`, `MFC42u.dll` |
| CD/image | no |
| Notes | **Pass Left** with the physical mouse is still unreliable |

### SimCity 2000 — `sc2k.ini` / `SimCity 2000.wex`

| | |
|---|---|
| Directory | prefix `C:\SC2K\` → `wineprefix-prebuilt/drive_c/SC2K/` |
| Executable | `SIMCITY.EXE` (Win95 tree, not DOS) |
| Sidecars | entire `WIN95/SC2K/` folder |
| CD/image | no |
| Notes | Do not run `SETUP.EXE` or sc2kfix. Saves: `C:\SC2K\Cities\` |

### Winamp 2.91 — `winamp2.ini` / `Winamp 2.wex`

| | |
|---|---|
| Directory | prefix `C:\Program Files\Winamp\` |
| Executable | `winamp.exe` |
| Sidecars | stock Winamp 2.91 install |
| CD/image | no |
| Notes | First-run / `out_wave.dll` applied by `ss1-winexe-winamp-config.sh`. OSD does not auto-play a track. Winamp is proprietary; install your own copy. |

### Command & Conquer Gold — `cnc.ini` / `Command & Conquer.wex`

| | |
|---|---|
| Directory | `/media/fat/Windows/apps/cnc/` |
| Executable | `C&C95.EXE` (Windows 95, not DOS `CONQUER.EXE`) |
| Sidecars | extracted InstallShield HDD files |
| CD/image | `/media/fat/Windows/iso/CnC_NOD95.iso` mounted as Wine D: |
| Notes | Do not run disc `SETUP.EXE`. PAL8 helper is optional. Performance is still an optimisation target. |

### Civilization II MGE — `civ2.ini` / `Civilization II.wex`

| | |
|---|---|
| Directory | `/media/fat/Windows/apps/civ2/` |
| Executable | `civ2.exe` |
| Sidecars | extracted HDD data; CD music PCM under `apps/civ2/cdaudio/track02.pcm`–`track12.pcm` |
| CD/image | data-track ISO as Wine D:; keep the original mixed-mode BIN/CUE intact |
| Notes | Do not run disc `SETUP.EXE`. Gameplay and music are proven. Advisor / High Council video is **unfinished**. |

### Windows Media Player 7.1 — parked

`profiles/experimental/wmp9.ini` is SSH-only (`menu=0`). Playback is
parked. Do not add WMP to the OSD list. See `docs/WMP9_DSHOW.md`
(historical filename; the parked player is **WMP 7.1**).
