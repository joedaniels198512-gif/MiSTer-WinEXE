# MiSTer WinEXE

WinEXE lets SuperStation One / MiSTer run selected classic 32-bit Windows applications and games.

It uses Box86 + Wine on the ARM side and a dedicated FPGA core for 640×480 HDMI/CRT output. It launches like a MiSTer core rather than booting a complete emulated PC.

It is experimental beta software.

These titles have been demonstrated. **None of them are included in the download.** You must add files you are legally allowed to use.

| Application | Status |
|---|---|
| Notepad | Working |
| Paint | Working |
| Minesweeper | Working |
| Solitaire | Working |
| FreeCell | Working |
| Winamp 2.91 | Working |
| SimCity 2000 | Working |
| Civilization II MGE | Working |
| Command & Conquer | Playable |
| Hearts | Minor issue |
| Windows Media Player 7.1 | Experimental |

## Installation

### 1. Download

Download:

**WinEXE-v0.1.0-beta.zip**

from the [GitHub Releases](https://github.com/joedaniels198512-gif/superstation-windows/releases) page.

### 2. Copy to the SD card

Extract the contents of the zip to the **root** of the MiSTer / SuperStation SD card.

The package already contains the redistributable WinEXE runtime, including:

- `WinEXE_<date>.rbf`
- `MiSTer_WinEXE`
- Wine 7.1
- Box86
- X11 runtime
- presenter
- clean Wine prefix
- profiles and launchers

You do **not** need to download separate GitHub Actions artifacts.

### 3. Boot and install

Boot the MiSTer / SuperStation. From the menu:

**Scripts → WinEXE Installer**

The installer configures WinEXE and installs the runtime.

The core is installed under `_Computer` as `WinEXE_<YYYYMMDD>.rbf` (for example `/media/fat/_Computer/WinEXE_20260918.rbf`).

SSH is not required for a normal installation.

### 4. Add Windows applications

WinEXE does **not** contain Microsoft software or commercial games.

Copy your own legally obtained 32-bit application files onto the SD card. For Notepad:

```text
/media/fat/games/WinEXE/apps/notepad.exe
```

Per-application folders and extra files: [Application setup](docs/APPS.md).

### 5. Launch WinEXE

From MiSTer:

**Computer → WinEXE**

Press **F12** to open the WinEXE OSD, choose **Load Application...**, and pick a `.wex` shortcut (for example `Notepad.wex`).

## What is WinEXE?

WinEXE is a lightweight compatibility layer, not a full Windows install and not a PC emulator like ao486. A Windows `.exe` is translated on the ARM Linux side (Box86 + Wine), drawn on a 640×480 desktop, and displayed by the FPGA core.

You start it from the MiSTer Computer menu, then pick an application from the OSD. The public zip ships the open-source runtime only. Application files stay yours.

## Current compatibility

| Application | Status | Notes |
|---|---|---|
| Notepad | Working | XP `notepad.exe` |
| Paint | Working | XP `mspaint.exe` |
| Minesweeper | Working | XP `winmine.exe` |
| Solitaire | Working | XP `sol.exe` + `cards.dll` |
| FreeCell | Working | XP `freecell.exe` + `cards.dll` |
| Winamp 2.91 | Working | UI and playback-state tested; audio still being refined |
| SimCity 2000 | Working | Win95 `C:\SC2K\` tree |
| Civilization II MGE | Working | Gameplay and music confirmed; advisor / High Council video unfinished |
| Command & Conquer | Playable | PAL8 path works; performance still being improved |
| Hearts | Minor issue | Plays; Pass Left with the physical mouse is unreliable |
| Windows Media Player 7.1 | Experimental | UI works; playback is unfinished |

See [docs/APPS.md](docs/APPS.md) for file names and folders. See [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) for limits.

## Adding applications

WinEXE does **not** include Windows applications. Copy 32-bit (PE32) files you are allowed to use:

```text
/media/fat/games/WinEXE/apps/notepad.exe
```

Then start **WinEXE** and choose `Notepad.wex` from the OSD.

Paint is `/media/fat/games/WinEXE/apps/mspaint.exe`. XP card games go in `/media/fat/games/WinEXE/apps/xp-games/`. Other titles have their own folders.

Full layout and CD notes: [Application setup](docs/APPS.md).

## Using WinEXE

All applications share one lightweight Windows session.

- **F12** opens the MiSTer OSD. USB keyboard and mouse stay with the Windows desktop when the OSD is closed.
- **Load Application...** starts the profile named by that `.wex`.
- **Restart** launches the same application again.
- **Stop** closes the current application and returns to **READY**.
- **Reset** is the stock core reset.

**READY** means X11, the presenter, and Wine’s desktop stay in memory so the next application can start quickly. You are not rebooting a PC each time.

Use a USB mouse and keyboard. WinEXE currently expects the mouse on `/dev/input/event0` and the keyboard on `/dev/input/event1`.

## Known limitations

- Experimental beta; each application is a separate compatibility case
- About 512 MB HPS RAM; large programs can run out
- A launch memory floor may refuse a start rather than crashing Linux
- Some apps do not hold a perfect 60 Hz picture
- C&C performance still needs work
- Civilization II advisor video is unfinished
- Hearts Pass Left is unreliable
- Windows Media Player playback is unfinished
- USB input assumes event0 = mouse, event1 = keyboard

Details: [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

## How it works

**Windows EXE → Box86 → Wine → 640×480 X11 desktop → WinEXE presenter → FPGA framebuffer → HDMI / CRT**

Box86 runs the x86 Wine binary on the Cortex-A9. Wine implements Windows APIs. A dummy Xorg server provides the 640×480 desktop. The presenter copies that picture into FPGA memory. `WinEXE.rbf` sends it through the MiSTer video pipeline.

More detail: [docs/WINEXE_CORE.md](docs/WINEXE_CORE.md), [docs/WINEXE_FPGA.md](docs/WINEXE_FPGA.md).

## Application files and copyright

WinEXE does **not** include Windows, Microsoft applications, commercial games, ISOs, ROMs, music, video, or other proprietary files.

The repository and the public zip contain the redistributable runtime, compatibility profiles, helpers, and documentation. You must provide your own legally obtained software.

Do not open issues or pull requests that attach copyrighted binaries.

## Building from source

Normal users should download **WinEXE-v0.1.0-beta.zip** from GitHub Releases. Nothing is compiled on the SuperStation.

Developers can rebuild individual pieces from this repository with GitHub Actions. The public release already assembles those pieces into one zip.

License and third-party notices: [LICENSE](LICENSE), [COPYING](COPYING), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Contributing

Compatibility reports and new profiles are welcome. Please include the application name, version, and relevant logs.

Do **not** upload proprietary binaries in issues or pull requests.
