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

X.Org 1.20.11 ARMHF + fbdev → `/dev/fb0` (`MiSTer_fb`) → 1920x1080,
depth 24 / 32 bpp, shadow framebuffer.

On the SuperStation, `xset q` answers on `:0` and `xsetroot` paints the
physical output. About 409 MB RAM stays available while Xorg is running.

See [docs/X11_RUNTIME.md](docs/X11_RUNTIME.md). Do not change the working
Wine, Box86, or prefix trees while adding `/media/fat/Windows/x11/`.

## Layout on the SuperStation

| Path | Role |
|---|---|
| `/media/fat/Windows/box86-ss1/box86` | Working Cortex-A9 Box86 |
| `/media/fat/Windows/wine-installer/opt/wine-devel/` | Wine 7.1 i386 |
| `/media/fat/Windows/wineprefix-prebuilt` | Prefix from GitHub Actions |
| `/media/fat/Windows/host-libs/` | Relocatable ARMHF fontconfig + deps |
| `/media/fat/Windows/x11/` | Relocatable X.Org + fbdev + winex11 client libs |

## Reproduce the prefix

See [docs/WINE_PREFIX.md](docs/WINE_PREFIX.md).
