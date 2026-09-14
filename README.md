# SuperStation Windows

Prepared Wine/Box86 pieces for running 32-bit Windows programs on a
SuperStation One (MiSTer Linux, Cortex-A9).

A normal install should be: copy/unzip a package onto `/media/fat/Windows`
and run a launcher. No Docker, compiler, or `wineboot` on the device.

## Current milestone

Prove Windows console execution:

`Windows cmd.exe` → Wine 7.1 i386 → Cortex-A9 Box86 → SuperStation ARM Linux

## Layout on the SuperStation

| Path | Role |
|---|---|
| `/media/fat/Windows/box86-ss1/box86` | Working Cortex-A9 Box86 |
| `/media/fat/Windows/wine-installer/opt/wine-devel/` | Wine 7.1 i386 |
| `/media/fat/Windows/wineprefix-prebuilt` | Prefix from GitHub Actions |

## Reproduce the prefix

See [docs/WINE_PREFIX.md](docs/WINE_PREFIX.md).
