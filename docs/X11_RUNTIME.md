# ARMHF X.Org runtime for SuperStation One

**Current WinEXE HDMI path** (proven 2026-09-16/17): dummy Xorg 640×480
RAM + evdev, presented by `ss1-winexe-x11-present` into FPGA DDR
`0x30000000`. See [WINEXE_FPGA.md](WINEXE_FPGA.md). Do not send Notepad,
Paint, Winamp, or SimCity 2000 through `/dev/fb0`.

The rest of this document is the **parked** HPS fbdev bundle that first
proved X.Org under `/media/fat/Windows`. Keep it so the runtime can be
rebuilt; do not polish ShadowFB/software-cursor corruption.

The console milestone is done. The parked display path was:

Wine / X11 → X.Org 1.20.11 ARMHF + fbdev → `/dev/fb0` (`MiSTer_fb`)

Proven on the SuperStation One:

- 1920x1080, depth 24 / 32 bpp, shadow framebuffer
- `xset q` answers on `:0`
- Xorg/`xsetroot`/Wine paint `/dev/fb0` (`MiSTer_fb`, HPS buffer **n=0**)
- the Menu core’s physical HDMI scanout is HPS buffer **n=1** (wallpaper)
- `scripts/ss1-fb-present.sh` copies n=0 → n=1 so that image is what HDMI shows
- about 409 MB RAM available while Xorg is running (~85 MB while builtin Notepad runs)
- everything lives under `/media/fat/Windows`; nothing is installed into `/usr`

The parked fbdev bundle does not change Wine, Box86, or the wineprefix.
WinEXE apps (Notepad, Paint, Winamp, SC2K) use dummy Xorg instead; see
[WINEXE_FPGA.md](WINEXE_FPGA.md).

## MiSTer HPS framebuffer scanout (required)

`/dev/fb0` being correct is **not** enough. The Menu core was loaded
(`/tmp/CORENAME=MENU`), `fb_terminal=1`, VT `tty1`, geometry 1920x1080x32.

MiSTer Main maps three HPS buffers at `FB_ADDR=0x22000000`:

| Buffer | Address | What writes it | What HDMI shows |
|---|---|---|---|
| n=0 | `0x22001000` (`/dev/fb0`) | Linux console, Xorg, Wine | only after `video_fb_enable(1, 0)` |
| n=1 | `0x227E9000` | Menu wallpaper (`SuperStationWireframe*`) | **yes — this is the live plane** |
| n=2 | next 8 MB | extra wallpaper slot | unused here |

That is why a framebuffer dump of `/dev/fb0` showed Notepad while the
physical display did not change: HDMI was still scanning n=1.

Official Main path to point the scaler at n=0 (`/dev/fb0`):

- **F9** on the Menu core (`fb_terminal=1`): `video_chvt(1)` +
  `video_fb_enable(!video_fb_state())` → SPI `UIO_SET_FBUF` `0x2F`
- **Scripts / pdf viewer** from the menu: `video_chvt(2)` +
  `video_fb_enable(1)` (n=0), then `agetty` on tty2
- `/dev/MiSTer_cmd` `fb_cmd*` only **reconfigures** mode if scanout is
  already n=0; it cannot enable it
- `echo screenshot` / `screenshot scaled` captures **core** video (the
  MENU snow), not the HPS overlay — do not use it as HDMI proof

SSH F9 injection into `/dev/input` did not reliably flip Main to n=0
(OSD timeout eats the first key; uinput rescans race). Direct
`UIO_SET_FBUF` from Python while Main was `SIGSTOP`’d did not get a
clean SPI ACK.

The working SSH/Linux handoff is therefore:

```sh
/media/fat/Windows/bin/ss1-xorg.sh start
# draw into /dev/fb0 as usual, then:
/media/fat/Windows/bin/ss1-fb-present.sh once
# or, while a GUI client runs:
/media/fat/Windows/bin/ss1-fb-present.sh loop 90
```

`ss1-fb-present.sh` mmap’s `/dev/mem` and copies 1920×1080×32 `/dev/fb0`
onto n=1. After that, the same pixels are in the buffer the Menu scaler
is already scanning. No Wine/Box86/prefix change. No input. No new core.

`vga_scaler=0` and `direct_video=0` are unchanged. This path is the HDMI
scaler + HPS wallpaper overlay, which is what the stock SS1 menu uses.

## How the bundle is produced

Workflow: `.github/workflows/prepare-x11-runtime.yml`

Script: `scripts/prepare-x11-runtime.sh`

On `ubuntu-22.04` the job downloads **Debian Bullseye armhf** debs from a
pinned `snapshot.debian.org` timestamp (`20220419T021707Z`, glibc 2.31)
and extracts them. Nothing is compiled.

## What is packaged

| Piece | Debian package | Role |
|---|---|---|
| X.Org 1.20.11 | `xserver-xorg-core`, `xserver-common` | Server |
| fbdev driver | `xserver-xorg-video-fbdev` | `/dev/fb0` |
| xkbcomp + keymap data | `x11-xkb-utils`, `xkb-data` | Server keyboard tables |
| `xset` / `xsetroot` / `xauth` | `x11-xserver-utils`, `xauth` | Path probe (not Wine) |
| misc bitmap fonts | `xfonts-base` (misc only), `xfonts-encodings` | Cursor / core fonts |
| winex11 client libs | `libx11-6` and the Xext/Xrandr/Xi/… set | Native ARM libs Box86 wraps |
| `libGL.so.1`, `libvulkan.so.1` | libglvnd + vulkan-loader + mesa *loaders* | winex11.drv `DT_NEEDED` |

### Deliberately omitted

- `libgl1-mesa-dri` and `libllvm11` (llvmpipe; too large for 512 MB)
- `mesa-vulkan-drivers` (loader only so the SONAME exists)
- `xserver-xorg-input-libinput` (evdev is enough for this USB mouse/keyboard)
- `keyboard-configuration`, `cpp-10`, `x11-utils` / `xdpyinfo`
- Anything installed globally

Bullseye `xserver-xorg-core` links `libselinux`, `libsystemd`, and
`libaudit`. The MiSTer image does not ship those SONAMEs; they are
included under `x11/lib` with `libpcre2-8`, `liblz4`, and `libzstd`.
They are not installed into `/usr`.

Glamor/GLX/DRI modules are disabled in `xorg.conf`. A real GLES/Vulkan
stack is not part of this milestone.

## Layout on the SuperStation

Extract to `/media/fat/Windows/x11/`:

| Path | Role |
|---|---|
| `lib/xorg/Xorg` | Server binary |
| `lib/xorg/modules/drivers/fbdev_drv.so` | Framebuffer driver |
| `lib/libX11.so.6` and friends | Native ARM client libs |
| `etc/X11/xorg.conf` | fbdev `/dev/fb0` plus static evdev on event0/event1 |
| `share/X11/xkb` | Relocatable xkb tree |
| `bin/xset`, `bin/xsetroot` | Probe that `:0` answers |

## Runtime

Input uses Debian `xserver-xorg-input-evdev` (not libinput). The physical
Pixart mouse is `/dev/input/event0` and the SIGMA keyboard is
`/dev/input/event1`. Those are wired as static `InputDevice` sections.
`GrabDevice` is off: MiSTer Main already has those nodes open, so an
exclusive grab fails. TinyUSB pico IR and `MiSTer virtual input` are
not attached to Xorg.

```sh
/media/fat/Windows/bin/ss1-mount-prefix.sh
/media/fat/Windows/bin/ss1-xorg.sh start
/media/fat/Windows/bin/ss1-fb-present.sh loop 600 &
/media/fat/Windows/bin/ss1-notepad.sh
```

Xorg 1.20 always execs `xkbcomp` from a compiled-in `/usr/bin` directory.
The SuperStation root filesystem is read-only, so the packager rewrites
that one string in **our** `Xorg` binary to `/tmp/bin`. The launcher
installs a tiny `/tmp/bin/xkbcomp` shim that copies the precompiled
`share/X11/default.xkm` (built on the Actions runner). Nothing is written
under `/usr`.

Input drivers (`mouse`, `kbd`, `libinput`) are not packaged yet. `xset`
and `xsetroot` are enough to prove `:0` is a real 1920x1080 screen.

`scripts/ss1-x11-env.sh` is for a future Wine GUI launcher. Do **not**
source it from `ss1-cmd.sh`. Console Wine must keep `DISPLAY` unset.

## Re-run

Actions → **Prepare ARMHF X11 fbdev runtime** → Run workflow.

Generated trees are **not** committed. Use the workflow artifact
`x11-runtime.tar.xz`.

WinEXE dummy Xorg also needs `dummy_drv.so` from the
**Build WinEXE X11 presenter** workflow, copied to
`x11/lib/xorg/modules/drivers/dummy_drv.so`. The parked fbdev
`xorg.conf` this packager writes is not the WinEXE config
(`scripts/xorg.winexe.conf`).

## PARKED: display-path architecture (2026-09-16)

Treat ShadowFB / software-cursor corruption as an **intermediate
architecture issue**. Do not spend time polishing the current Xorg
`/dev/fb0` path. Application compatibility work should ignore cosmetic
tearing unless it blocks testing.

Recorded facts:

- **Preferred temporary output:** F9 / Main `video_fb_enable(1, 0)` —
  HPS plane **n=0** is `/dev/fb0`. Wine → Xorg → fb0 → HDMI, one owner.
- **`/dev/fb0` corruption** is Xorg ShadowFB + software cursor interacting
  with `MiSTer_fb` reinitialisation and stale hardware pixels (black /
  navy-blue save-under blocks). It is already in the source framebuffer,
  not only on HDMI.
- **`ss1-fb-present` / n=1 is not the primary cause.** It copies fb0
  onto the Menu wallpaper plane. It should ultimately disappear.
- **Long term:** a dedicated WinEXE MiSTer FPGA core should own video
  (same idea as the DVD core’s private DDR buffers), not hijack MENU
  wallpaper.
- **Cheap interim fixes later (not now):** full X redraw after fb
  reinit (`xsetroot` / `xrefresh`); unbind fbcon on the X VT; stop the
  n=1 presenter once n=0 owns HDMI; launch via Main Scripts so
  `video_chvt(2)` + `video_fb_enable(1)` happens at start.
