# SuperStation Windows

Prepared Wine/Box86 pieces for running 32-bit Windows programs on a
SuperStation One (MiSTer Linux, Cortex-A9).

A normal install should be: copy/unzip a package onto `/media/fat/Windows`
and run a launcher. No Docker, compiler, or `wineboot` on the device.

GitHub: [joedaniels198512-gif/superstation-windows](https://github.com/joedaniels198512-gif/superstation-windows)

## Current status (2026-09-17)

Live path (do not use `/dev/fb0` / F9 / `ss1-fb-present` for these apps):

```
Wine 7.1 i386 → Box86 → dummy Xorg 640×480 RAM
  → ss1-winexe-x11-present (SHM + XFixes cursor)
  → /dev/mem 0x30000000 BGRX stride 2560
  → WinEXE_Test.rbf ascal → HDMI
```

### PROVEN

* genuine XP Notepad (`apps/notepad.exe`, 5.1.2600.5512)
* genuine XP Paint (`apps/mspaint.exe`; drop `MFC42u.dll` from the same ISO if needed)
* Winamp 2.91 with physical audio and MP3 playback
* original Win95 SimCity 2000 (`C:\SC2K\SIMCITY.EXE`)
* FPGA-backed 640×480 display (`WinEXE_Test.rbf`, colour bars then GUI)
* USB keyboard/mouse on dummy Xorg (evdev event0/event1, `GrabDevice false`)
* OSD input recovery (`ss1-winexe-keep-input.sh` ungrabs mouse/keyboard after OSD close)
* 30 Hz + dirty-region SC2K optimization (skip unchanged frames, 32×32 dirty spans)
* SC2K CPU affinity (SIMCITY on CPU0, presenter+Xorg on CPU1)
* SC2K floating toolbar stays above the city map (`ss1-winexe-sc2k-toolbar.sh`)

### Frozen / do not casually change

FPGA core sources and HDMI timing, dummy-X video path, Box86, Wine 7.1,
and the prebuilt prefix layout. Application work should stay in launchers
and the ARM presenter unless a specific app failure requires more.

### Parked

Xorg `/dev/fb0` ShadowFB/software-cursor corruption and the n=1 HPS
presenter. That path still exists for history; WinEXE HDMI does not use it.
See [docs/X11_RUNTIME.md](docs/X11_RUNTIME.md).

### Not in git (copyrighted / generated)

Genuine EXEs, the SC2K tree, Winamp, MP3s, Wine prefix images, X11/host-libs
tarballs, and compiled `.rbf` / presenter binaries. Rebuild those from
Actions artifacts + your own media. See below.

## Layout on the SuperStation

| Path | Role |
|---|---|
| `/media/fat/Windows/box86-ss1/box86` | Working Cortex-A9 Box86 |
| `/media/fat/Windows/wine-installer/opt/wine-devel/` | Wine 7.1 i386 |
| `/media/fat/Windows/wineprefix-prebuilt.ext4` | Prefix image (loop-mounted) |
| `/media/fat/Windows/wineprefix-prebuilt` | Mount point (`ss1-mount-prefix.sh`) |
| `/media/fat/Windows/host-libs/` | Relocatable ARMHF fontconfig + deps |
| `/media/fat/Windows/x11/` | Relocatable X.Org + dummy + evdev + winex11 libs |
| `/media/fat/Windows/bin/` | Launchers + ARM presenter from this repo / Actions |
| `/media/fat/Windows/apps/` | Drop genuine PE32 EXEs (Notepad, Paint, …) |
| `/media/fat/WinEXE_Test.rbf` | FPGA core from Actions |

## Launchers

| Script | What it starts |
|---|---|
| `scripts/ss1-winexe-notepad.sh` | Load core if needed, dummy Xorg, presenter, XP Notepad |
| `scripts/ss1-winexe-run-exe.sh` | Next EXE on the existing stack (default: Paint) |
| `scripts/ss1-winexe-winamp.sh` | Stamp first-run/Gecko-off settings, launch Winamp 2.91 |
| `scripts/ss1-winexe-sc2k.sh` | 30 Hz + dirty + affinity + registry stamp + toolbar watcher |
| `scripts/ss1-winexe-stop-wine.sh` | End the current Wine session only (keep Xorg/presenter/input) |

Presenter profiles (`scripts/ss1-winexe-present-restart.sh`):

| App | `SS1_HZ` | skip | dirty |
|---|---|---|---|
| Notepad / Paint / Winamp | 60 | on | off |
| SimCity 2000 | 30 | on | 32×32, 60% fallback |

HDMI and dummy X stay 60 Hz. Only ARM DDR writes are paced.

## Reconstruct the runtime

1. Clone this repository.
2. GitHub Actions artifacts (do not compile on the SuperStation):
   - **Build WinEXE_Test FPGA core** → `WinEXE_Test.rbf`
   - **Build WinEXE presenter** → `ss1-winexe-x11-present` plus `dummy_drv.so`
   - **Prepare Wine 7.1 win32 prefix** → `wineprefix-prebuilt` (then pack as `.ext4` if the SD is exFAT)
   - **Prepare ARMHF X11 runtime** → `x11-runtime.tar.xz` (fbdev + evdev; dummy comes from the presenter job)
   - **Prepare ARMHF host-libs** → fontconfig bundle
3. Copy the working Box86 + Wine 7.1 trees onto `/media/fat/Windows` (already
   proven on this SuperStation; do not replace casually).
4. Install scripts from `scripts/` to `/media/fat/Windows/bin/`. Copy
   `dummy_drv.so` to `/media/fat/Windows/x11/lib/xorg/modules/drivers/`.
5. Drop genuine media on the device only:
   - `apps/notepad.exe`, `apps/mspaint.exe` (+ `MFC42u.dll` if Paint asks)
   - Winamp 2.91 into `C:\Program Files\Winamp`
   - Win95 `WIN95/SC2K/` tree to `C:\SC2K\`
6. Load `WinEXE_Test.rbf`, start dummy Xorg + presenter, then a launcher.

Details: [docs/WINEXE_FPGA.md](docs/WINEXE_FPGA.md),
[docs/X11_RUNTIME.md](docs/X11_RUNTIME.md),
[docs/WINE_PREFIX.md](docs/WINE_PREFIX.md),
[docs/HOST_LIBS.md](docs/HOST_LIBS.md).

Do not change the working Wine, Box86, or prefix trees while adding
`/media/fat/Windows/x11/`.
