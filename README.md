# SuperStation Windows

Prepared Wine/Box86 pieces for running 32-bit Windows programs on a
SuperStation One (MiSTer Linux, Cortex-A9).

A normal install should be: copy/unzip a package onto `/media/fat/Windows`
and run a launcher. No Docker, compiler, or `wineboot` on the device.

## Current milestones

Windows console execution works:

`cmd.exe /c echo HELLO FROM WINDOWS ON SUPERSTATION`

via Wine 7.1 i386 → Cortex-A9 Box86.

The display path also works, self-contained under `/media/fat/Windows`
(nothing installed into `/usr`):

X.Org 1.20.11 ARMHF + fbdev → `/dev/fb0` (`MiSTer_fb`) → 1920x1080.

Physical HDMI: F9 / `video_fb_enable(1,0)` scans HPS **n=0** (`/dev/fb0`).
The n=1 Python presenter is a fallback and should disappear. Display
corruption from ShadowFB/software cursor is parked; do not polish that
path while testing real Windows EXEs. Details:
[docs/X11_RUNTIME.md](docs/X11_RUNTIME.md).

## Layout on the SuperStation

| Path | Role |
|---|---|
| `/media/fat/Windows/box86-ss1/box86` | Working Cortex-A9 Box86 |
| `/media/fat/Windows/wine-installer/opt/wine-devel/` | Wine 7.1 i386 |
| `/media/fat/Windows/wineprefix-prebuilt` | Prefix from GitHub Actions |
| `/media/fat/Windows/host-libs/` | Relocatable ARMHF fontconfig + deps |
| `/media/fat/Windows/x11/` | Relocatable X.Org + fbdev + winex11 client libs |
| `/media/fat/Windows/apps/` | Drop genuine PE32 EXEs here; `ss1-run-exe.sh` launches them |

Wine builtin Notepad (input + window) is a **passed** milestone.
Cosmetic ShadowFB/software-cursor tearing is **parked** — see
[docs/X11_RUNTIME.md](docs/X11_RUNTIME.md). Next: user-supplied
Microsoft Notepad, then Paint, via `scripts/ss1-run-exe.sh`.

Do not change the working Wine, Box86, or prefix trees while adding
`/media/fat/Windows/x11/`.

FPGA display core (`fpga/`, Quartus 17 via GitHub Actions):
[docs/WINEXE_FPGA.md](docs/WINEXE_FPGA.md). First HDMI milestone is
`WinEXE_Test.rbf` plus ARM colour bars at `0x30000000`, not Wine.

## Reproduce the prefix

See [docs/WINE_PREFIX.md](docs/WINE_PREFIX.md).
