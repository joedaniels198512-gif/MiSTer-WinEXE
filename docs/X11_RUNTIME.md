# ARMHF X.Org + fbdev runtime for SuperStation One

The console milestone is done. This bundle is the display path:

Wine / X11 → X.Org 1.20.11 ARMHF + fbdev → `/dev/fb0` (`MiSTer_fb`)

Proven on the SuperStation One:

- 1920x1080, depth 24 / 32 bpp, shadow framebuffer
- `xset q` answers on `:0`
- `xsetroot` paints the physical HDMI/framebuffer output
- about 409 MB RAM available while Xorg is running
- everything lives under `/media/fat/Windows`; nothing is installed into `/usr`

It does not change Wine, Box86, or the wineprefix. WMP, Winamp, and audio
are out of scope.

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
- `xserver-xorg-input-*` (no input yet; `AutoAddDevices` is off)
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
| `etc/X11/xorg.conf` | fbdev → `/dev/fb0`, 1920x1080, no input |
| `share/X11/xkb` | Relocatable xkb tree |
| `bin/xset`, `bin/xsetroot` | Probe that `:0` answers |

## Runtime

```sh
/media/fat/Windows/bin/ss1-xorg.sh start
/media/fat/Windows/bin/ss1-xorg.sh probe
/media/fat/Windows/bin/ss1-xorg.sh stop
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
