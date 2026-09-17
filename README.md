# SuperStation Windows

Prepared Wine/Box86 pieces for running 32-bit Windows programs on a
SuperStation One (MiSTer Linux, Cortex-A9).

A normal install should be: copy/unzip a package onto `/media/fat/Windows`
and run a launcher. No Docker, compiler, or `wineboot` on the device.

GitHub: [joedaniels198512-gif/superstation-windows](https://github.com/joedaniels198512-gif/superstation-windows)

## Current status (2026-09-17)

**WMP is parked.** Do not continue WMP memory/audio work. Do not start C&C.
Next milestone: one shared `WinEXE.rbf` with OSD application profiles.
Architecture (no Quartus yet): [docs/WINEXE_CORE.md](docs/WINEXE_CORE.md).

Live path (do not use `/dev/fb0` / F9 / `ss1-fb-present` for these apps):

```
Wine 7.1 i386 → Box86 → dummy Xorg 640×480 RAM
  → ss1-winexe-x11-present (SHM + XFixes cursor)
  → /dev/mem 0x30000000 BGRX stride 2560
  → WinEXE_Test.rbf ascal → HDMI
```

Multimedia (WMP / DirectShow) uses **`box86-gstflow`** only. The original
`box86` binary is the untouched rollback and remains the default Wine
loader. Full write-up: [docs/WMP9_DSHOW.md](docs/WMP9_DSHOW.md).

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
* (parked) genuine XP SP3 WMP9 9.00.00.4503 UI launches
* (parked) Wine DirectShow PCM WAV graph and physical WaveOut audio

### WMP9 — PARKED (kept, not in the OSD app list)

Do **not** continue this work now. Sources stay in the repo: Box86
GStreamer patches, `box86-gstflow`, GStreamer runtime, DirectShow
harness, `ss1waveout.ax`, `docs/WMP9_DSHOW.md`. SSH-only via
`ss1-winexe-wmp9.sh` / `profiles/experimental/wmp9.ini`. OSD list is
Notepad, Paint, Winamp 2, SimCity 2000.

### WMP9 / DirectShow / GStreamer / WaveOut status (parked notes)

* **WMP UI works.** Genuine `wmplayer.exe` 9.00.00.4503 launches on the
  existing WinEXE stack via `ss1-winexe-wmp9.sh` / `wine-gstflow`.
* **PCM playback works.** Minimal graph under `box86-gstflow`: Reader →
  GStreamer splitter → audio renderer. Duration, Running state, real-time
  position, and `EC_COMPLETE` are proven.
* **Physical audio works.** Heard on SuperStation HDMI/line out through
  winealsa.
* **DirectSound is unstable.** Wine 7.1 maps both `CLSID_AudioRender` and
  `CLSID_DSoundRender` to the DirectSound renderer. It drops samples and
  crackles even with no WMP. Do not treat registry merits as a WaveOut
  fix. Do not load XP quartz.
* **Custom WaveOut renderer is the current preferred path.** Private
  CLSID `{B7E3C101-5A42-4D8F-9C1E-A1B2C3D4E5F6}`, `DllGetClassObject`
  only (no `regsvr32`). Path: DirectShow → GStreamer splitter →
  `ss1waveout.ax` → WinMM `waveOut*` → winealsa.
* **Best-known config:** 12 × 30 ms buffers (~360 ms), prime 9 before
  `waveOutRestart`, 44.1 kHz / 16-bit / stereo. Physical listen: seemed
  really good. 30 s PCM: 5,292,000 bytes received = submitted =
  completed, dropped 0. One ~1095 ms Receive stall at t≈15.3 s; remaining
  stutter source is upstream producer/scheduling stalls, not WaveOut
  dropping data.
* **Not yet tested** through the final WaveOut path: MP3, WMP
  visualisations, WMP memory usage, wiring `ss1waveout.ax` into actual
  WMP9 (best audio so far is the harness).
* Do **not** implement `IReferenceClock`. Do **not** replace original
  Box86. WMP next blocker is `wmplayer.exe` RAM, not the renderer.
  Resume only after the WinEXE OSD core. Do not start C&C.

### Frozen / do not casually change

FPGA core sources and HDMI timing, dummy-X video path, the original
Box86 binary, Wine 7.1, and the prebuilt prefix layout. Application work
should stay in launchers and the ARM presenter unless a specific app
failure requires more. Multimedia tests use sidecar `box86-gst` /
`box86-gstflow` binaries only.

### Parked

* Windows Media Player 9 / DirectShow / WaveOut — kept on disk, **not** in
  the OSD app list. See [docs/WMP9_DSHOW.md](docs/WMP9_DSHOW.md).
* Xorg `/dev/fb0` ShadowFB/software-cursor corruption and the n=1 HPS
  presenter. That path still exists for history; WinEXE HDMI does not use it.
  See [docs/X11_RUNTIME.md](docs/X11_RUNTIME.md).

### Not in git (copyrighted / generated)

Genuine EXEs, the SC2K tree, Winamp, XP WMP9 binaries, MP3s, Wine prefix
images, X11/host-libs tarballs, and compiled `.rbf` / presenter binaries.
Rebuild those from Actions artifacts + your own media. See below.

## Layout on the SuperStation

| Path | Role |
|---|---|
| `/media/fat/Windows/box86-ss1/box86` | Original Cortex-A9 Box86 (untouched rollback) |
| `/media/fat/Windows/box86-ss1/box86-gst` | GStreamer factory/plugin Box86 (sidecar) |
| `/media/fat/Windows/box86-ss1/box86-gstflow` | Working multimedia Box86 (sidecar; WMP/DShow) |
| `/media/fat/Windows/wine-installer/opt/wine-devel/` | Wine 7.1 i386 |
| `/media/fat/Windows/wineprefix-prebuilt.ext4` | Prefix image (loop-mounted) |
| `/media/fat/Windows/wineprefix-prebuilt` | Mount point (`ss1-mount-prefix.sh`) |
| `/media/fat/Windows/host-libs/` | Relocatable ARMHF fontconfig + deps |
| `/media/fat/Windows/x11/` | Relocatable X.Org + dummy + evdev + winex11 libs |
| `/media/fat/Windows/bin/` | Launchers + ARM presenter from this repo / Actions |
| `/media/fat/Windows/apps/` | Drop genuine PE32 EXEs (Notepad, Paint, …) |
| `/media/fat/Windows/profiles/` | OSD application INI files (no EXEs) |
| `/media/fat/WinEXE_Test.rbf` | current FPGA core (rename to `WinEXE.rbf` after first OSD build) |

## Launchers

| Script | What it starts |
|---|---|
| `scripts/ss1-winexe-launch.sh` | Generic profile launcher (launch/osd/restart/stop/status) |
| `scripts/ss1-winexe-notepad.sh` | Wrapper → `launch notepad` |
| `scripts/ss1-winexe-run-exe.sh` | Paint profile, or ad-hoc EXE on the 60 Hz stack |
| `scripts/ss1-winexe-winamp.sh` | Wrapper → `launch winamp2` (optional MP3 still allowed) |
| `scripts/ss1-winexe-sc2k.sh` | Wrapper → `launch sc2k` (fixes live in `profiles/sc2k.ini`) |
| `scripts/ss1-winexe-stop-wine.sh` | End the current Wine session only (keep Xorg/presenter/input) |
| `scripts/ss1-winexe-wmp9.sh` | PARKED — genuine WMP9 via `wine-gstflow` |
| `scripts/ss1-winexe-dshow.sh` | PARKED — PCM DirectShow harness → `ss1waveout.ax` |

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
4. Install scripts from `scripts/` to `/media/fat/Windows/bin/` and
   profiles to `/media/fat/Windows/profiles/`
   (`ss1-winexe-install-layout.sh`). Copy `dummy_drv.so` to
   `/media/fat/Windows/x11/lib/xorg/modules/drivers/`.
5. Drop genuine media on the device only:
   - `apps/notepad.exe`, `apps/mspaint.exe` (+ `MFC42u.dll` if Paint asks)
   - Winamp 2.91 into `C:\Program Files\Winamp`
   - Win95 `WIN95/SC2K/` tree to `C:\SC2K\`
   - WMP9 files into `/media/fat/Windows/apps/wmp9/` then `ss1-winexe-wmp9-install.sh`
6. Load `WinEXE_Test.rbf` (today) or `WinEXE.rbf` (after the OSD FPGA
   build), then `ss1-winexe-launch.sh launch notepad`.

Details: [docs/WINEXE_CORE.md](docs/WINEXE_CORE.md),
[docs/WINEXE_FPGA.md](docs/WINEXE_FPGA.md),
[docs/WMP9_DSHOW.md](docs/WMP9_DSHOW.md),
[docs/X11_RUNTIME.md](docs/X11_RUNTIME.md),
[docs/WINE_PREFIX.md](docs/WINE_PREFIX.md),
[docs/HOST_LIBS.md](docs/HOST_LIBS.md).

Do not change the working Wine, Box86, or prefix trees while adding
`/media/fat/Windows/x11/`.
