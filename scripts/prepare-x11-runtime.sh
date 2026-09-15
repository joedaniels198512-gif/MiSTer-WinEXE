#!/usr/bin/env bash
# Build a relocatable Debian Bullseye armhf X.Org + fbdev runtime for SuperStation One.
# Extracts packages; does not compile. Intended for GitHub Actions (x86_64).
# Does not touch Wine, Box86, or the wineprefix.
set -euo pipefail

OUT_DIR="${OUT_DIR:-$(pwd)/x11}"
WORKDIR="${WORKDIR:-$(pwd)/.x11-work}"
OUT_TAR="${OUT_TAR:-$(pwd)/x11-runtime.tar.xz}"
ROOT="${X11_ROOT:-/media/fat/Windows/x11}"

# Pinned Debian Bullseye-era armhf debs (glibc 2.31) via snapshot.debian.org.
# Intentionally omits libgl1-mesa-dri / libllvm11 (tens of MB, not needed for
# fbdev 2D). winex11.drv still gets libGL.so.1 + libvulkan.so.1 so Box86 can
# dlopen the driver; DRI/ICD are not shipped.
PACKAGE_URLS=(
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/xorg-server/xserver-xorg-core_1.20.11-1+deb11u1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/xserver-xorg-video-fbdev/xserver-xorg-video-fbdev_0.5.0-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/xorg-server/xserver-common_1.20.11-1+deb11u1_all.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/xorg/x11-common_7.7+22_all.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/x11-xkb-utils/x11-xkb-utils_7.7+5_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/xkeyboard-config/xkb-data_2.29-2_all.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/x11-xserver-utils/x11-xserver-utils_7.7+8_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/xauth/xauth_1.1-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/xfonts-base/xfonts-base_1.0.5_all.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/x/xfonts-encodings/xfonts-encodings_1.0.4-2.1_all.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libx11/libx11-6_1.7.2-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libx11/libx11-data_1.7.2-1_all.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libx11/libx11-xcb1_1.7.2-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxext/libxext6_1.3.3-1.1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxfixes/libxfixes3_5.0.3-2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcursor/libxcursor1_1.2.0-2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxi/libxi6_1.7.10-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcomposite/libxcomposite1_0.4.5-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxinerama/libxinerama1_1.1.4-2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxrender/libxrender1_0.9.10-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxrandr/libxrandr2_1.5.1-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxxf86vm/libxxf86vm1_1.1.4-1+b2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxdamage/libxdamage1_1.1.5-2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcb/libxcb1_1.14-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcb/libxcb-dri2-0_1.14-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcb/libxcb-dri3-0_1.14-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcb/libxcb-glx0_1.14-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcb/libxcb-present0_1.14-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcb/libxcb-shm0_1.14-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcb/libxcb-sync1_1.14-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcb/libxcb-xfixes0_1.14-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxcb/libxcb-shape0_1.14-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxau/libxau6_1.0.9-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxdmcp/libxdmcp6_1.1.2-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libb/libbsd/libbsd0_0.11.3-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libm/libmd/libmd0_1.0.3-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxshmfence/libxshmfence1_1.3-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxfont/libxfont2_2.0.4-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libf/libfontenc/libfontenc1_1.1.4-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/p/pixman/libpixman-1-0_0.40.0-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libp/libpciaccess/libpciaccess0_0.16-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libe/libepoxy/libepoxy0_1.5.5-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libd/libdrm/libdrm2_2.4.104-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libd/libdrm/libdrm-common_2.4.104-1_all.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libu/libunwind/libunwind8_1.3.2-2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libg/libglvnd/libglvnd0_1.3.2-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libg/libglvnd/libgl1_1.3.2-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libg/libglvnd/libglx0_1.3.2-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/m/mesa/libglx-mesa0_20.3.5-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/m/mesa/libglapi-mesa_20.3.5-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libg/libglvnd/libegl1_1.3.2-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/m/mesa/libegl-mesa0_20.3.5-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libg/libglvnd/libgles2_1.3.2-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/m/mesa/libgbm1_20.3.5-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/w/wayland/libwayland-client0_1.18.0-2~exp1.1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/w/wayland/libwayland-server0_1.18.0-2~exp1.1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/v/vulkan-loader/libvulkan1_1.2.162.0-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxkbfile/libxkbfile1_1.1.0-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxaw/libxaw7_1.0.13-1.1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxt/libxt6_1.2.0-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxmu/libxmu6_1.1.2-2+b3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxpm/libxpm4_3.5.12-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libi/libice/libice6_1.0.10-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libs/libsm/libsm6_1.2.3-1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libx/libxmu/libxmuu1_1.1.2-2+b3_armhf.deb"
  # Xorg NEEDED libs that the MiSTer image does not ship (keep under x11/lib).
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libs/libselinux/libselinux1_3.1-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/p/pcre2/libpcre2-8-0_10.36-2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/a/audit/libaudit1_3.0-2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/s/systemd/libsystemd0_247.3-7_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/l/lz4/liblz4-1_1.9.3-2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libz/libzstd/libzstd1_1.4.8+dfsg-2.1_armhf.deb"
)

log() { printf '%s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

download() {
  local url="$1" dest="$2"
  if command -v wget >/dev/null 2>&1; then
    wget -q --user-agent="ss1-x11-runtime/1.0" -O "$dest" "$url"
  else
    require_cmd curl
    curl -fsSL -A "ss1-x11-runtime/1.0" -o "$dest" "$url"
  fi
}

extract_deb() {
  local deb="$1" dest="$2"
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -x "$deb" "$dest"
    return
  fi
  require_cmd ar
  require_cmd tar
  local tmp
  tmp=$(mktemp -d)
  (cd "$tmp" && ar -x "$deb")
  if [ -f "$tmp/data.tar.xz" ]; then
    tar -C "$dest" -xJf "$tmp/data.tar.xz"
  elif [ -f "$tmp/data.tar.gz" ]; then
    tar -C "$dest" -xzf "$tmp/data.tar.gz"
  elif [ -f "$tmp/data.tar.zst" ]; then
    tar -C "$dest" --zstd -xf "$tmp/data.tar.zst"
  else
    echo "unknown data archive in $deb" >&2
    ls -la "$tmp" >&2
    rm -rf "$tmp"
    exit 1
  fi
  rm -rf "$tmp"
}

require_cmd tar
require_cmd xz
require_cmd find

rm -rf "$WORKDIR/debs" "$WORKDIR/extract" "$OUT_DIR"
mkdir -p "$WORKDIR/debs" "$WORKDIR/extract" \
  "$OUT_DIR/bin" "$OUT_DIR/lib" "$OUT_DIR/lib/xorg/modules" \
  "$OUT_DIR/share/X11" "$OUT_DIR/share/fonts/X11" \
  "$OUT_DIR/etc/X11/xorg.conf.d"

for url in "${PACKAGE_URLS[@]}"; do
  base=$(basename "${url%%\?*}")
  log "Downloading $base"
  download "$url" "$WORKDIR/debs/$base"
  extract_deb "$WORKDIR/debs/$base" "$WORKDIR/extract"
done

# Flatten shared libraries, including SONAME symlinks.
for dir in \
  "$WORKDIR/extract/usr/lib/arm-linux-gnueabihf" \
  "$WORKDIR/extract/lib/arm-linux-gnueabihf" \
  "$WORKDIR/extract/usr/lib"
do
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 \( -name 'lib*.so*' -o -name '*.so' \) -exec cp -a {} "$OUT_DIR/lib/" \;
  fi
done
(
  cd "$OUT_DIR/lib"
  for real in lib*.so.[0-9]*.[0-9]*; do
    [ -e "$real" ] || continue
    soname=$(echo "$real" | sed -E 's/(\.so\.[0-9]+)\..*/\1/')
    [ -e "$soname" ] || ln -sf "$real" "$soname"
  done
)

# Xorg binary + modules (core + fbdev only).
if [ -x "$WORKDIR/extract/usr/lib/xorg/Xorg" ]; then
  mkdir -p "$OUT_DIR/lib/xorg"
  cp -a "$WORKDIR/extract/usr/lib/xorg/Xorg" "$OUT_DIR/lib/xorg/Xorg"
  ln -sfn ../lib/xorg/Xorg "$OUT_DIR/bin/Xorg"
elif [ -x "$WORKDIR/extract/usr/bin/Xorg" ]; then
  cp -a "$WORKDIR/extract/usr/bin/Xorg" "$OUT_DIR/bin/Xorg"
fi
# Xorg concatenates the compiled-in dir "/usr/bin" + "xkbcomp". Root on the
# SuperStation is read-only; retarget the directory string in OUR copy only.
if [ -f "$OUT_DIR/lib/xorg/Xorg" ]; then
  python3 - "$OUT_DIR/lib/xorg/Xorg" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
data = p.read_bytes()
old, new = b"/usr/bin\0", b"/tmp/bin\0"
n = data.count(old)
if n != 1:
    raise SystemExit("expected one /usr/bin string in Xorg, found %d" % n)
p.write_bytes(data.replace(old, new, 1))
print("patched Xorg xkbcomp dir /usr/bin -> /tmp/bin")
PY
fi
if [ -d "$WORKDIR/extract/usr/lib/xorg/modules" ]; then
  cp -a "$WORKDIR/extract/usr/lib/xorg/modules/." "$OUT_DIR/lib/xorg/modules/"
fi
if [ -f "$WORKDIR/extract/usr/lib/xorg/protocol.txt" ]; then
  cp -a "$WORKDIR/extract/usr/lib/xorg/protocol.txt" "$OUT_DIR/lib/xorg/protocol.txt"
fi

# Client / helper binaries used to prove the display path (not Wine).
for bin in xkbcomp xset xsetroot xauth; do
  if [ -x "$WORKDIR/extract/usr/bin/$bin" ]; then
    cp -a "$WORKDIR/extract/usr/bin/$bin" "$OUT_DIR/bin/"
  fi
done

# Keyboard data + X rgb database.
if [ -d "$WORKDIR/extract/usr/share/X11/xkb" ]; then
  cp -a "$WORKDIR/extract/usr/share/X11/xkb" "$OUT_DIR/share/X11/xkb"
fi
# Precompiled keymap (arch-independent). Xorg still execs xkbcomp; the
# launcher can copy this file to /tmp/server-0.xkm.
cat > "$WORKDIR/default.xkb" <<'EOF'
xkb_keymap {
    xkb_keycodes  { include "evdev+aliases(qwerty)" };
    xkb_types     { include "complete" };
    xkb_compat    { include "complete" };
    xkb_symbols   { include "pc+us+inet(evdev)" };
    xkb_geometry  { include "pc(pc105)" };
};
EOF
if command -v xkbcomp >/dev/null 2>&1; then
  xkbcomp -w 0 -I"$OUT_DIR/share/X11/xkb" "$WORKDIR/default.xkb" "$OUT_DIR/share/X11/default.xkm" || true
fi
if [ ! -f "$OUT_DIR/share/X11/default.xkm" ]; then
  log "WARN: default.xkm not built on this host (install x11-xkb-utils)"
fi
if [ -f "$WORKDIR/extract/usr/share/X11/rgb.txt" ]; then
  cp -a "$WORKDIR/extract/usr/share/X11/rgb.txt" "$OUT_DIR/share/X11/rgb.txt"
fi
if [ -d "$WORKDIR/extract/usr/share/X11/locale" ]; then
  cp -a "$WORKDIR/extract/usr/share/X11/locale" "$OUT_DIR/share/X11/locale"
fi

# Bitmap fonts: misc + encodings only (skip 75/100dpi).
if [ -d "$WORKDIR/extract/usr/share/fonts/X11/misc" ]; then
  cp -a "$WORKDIR/extract/usr/share/fonts/X11/misc" "$OUT_DIR/share/fonts/X11/misc"
fi
if [ -d "$WORKDIR/extract/usr/share/fonts/X11/encodings" ]; then
  cp -a "$WORKDIR/extract/usr/share/fonts/X11/encodings" "$OUT_DIR/share/fonts/X11/encodings"
fi

# Relocatable xorg.conf aimed at MiSTer_fb /dev/fb0. No input devices yet.
cat > "$OUT_DIR/etc/X11/xorg.conf" <<EOF
Section "ServerLayout"
    Identifier     "SuperStation"
    Screen         0 "Screen0"
EndSection

Section "Files"
    ModulePath     "$ROOT/lib/xorg/modules"
    FontPath       "$ROOT/share/fonts/X11/misc"
    FontPath       "$ROOT/share/fonts/X11/encodings"
EndSection

Section "Module"
    Disable        "glx"
    Disable        "glamoregl"
    Disable        "dri"
    Disable        "dri2"
EndSection

Section "ServerFlags"
    Option         "AutoAddDevices" "false"
    Option         "AutoEnableDevices" "false"
    Option         "AutoAddGPU" "false"
    Option         "AllowMouseOpenFail" "true"
    Option         "DontZap" "false"
    Option         "XkbDisable" "true"
EndSection

Section "Device"
    Identifier     "Card0"
    Driver         "fbdev"
    Option         "fbdev" "/dev/fb0"
    Option         "ShadowFB" "true"
EndSection

Section "Monitor"
    Identifier     "Monitor0"
    Option         "Enable" "true"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Card0"
    Monitor        "Monitor0"
    DefaultDepth   24
    SubSection     "Display"
        Depth      24
    EndSubSection
EndSection

EOF

# Minimal later-Wine env helper is shipped by scripts/ss1-x11-env.sh in git.
cat > "$OUT_DIR/X11_MANIFEST.txt" <<EOF
purpose=relocatable ARMHF X.Org + fbdev runtime for SuperStation One
debian_snapshot=20220419T021707Z Bullseye armhf
arch=armhf
glibc_target=2.31
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
root=$ROOT
display_target=/dev/fb0 MiSTer_fb 1920x1080x32
omitted=libgl1-mesa-dri libllvm11 mesa-vulkan-drivers xserver-xorg-input-* cpp-10
winex11_client_libs=libX11 libXext libXfixes libXcursor libXi libGL libvulkan libXcomposite libXinerama libXrender libXrandr libXxf86vm
notes=Do not install into /usr. Launch with scripts/ss1-xorg.sh. Do not change Wine/Box86/prefix.
packages=${PACKAGE_URLS[*]}
EOF

if command -v arm-linux-gnueabihf-readelf >/dev/null 2>&1; then
  READELF=arm-linux-gnueabihf-readelf
elif command -v readelf >/dev/null 2>&1; then
  READELF=readelf
else
  READELF=
fi

if [ -n "$READELF" ]; then
  {
    for f in \
      "$OUT_DIR/lib/xorg/Xorg" \
      "$OUT_DIR/lib/xorg/modules/drivers/fbdev_drv.so" \
      "$OUT_DIR/lib/libX11.so.6" \
      "$OUT_DIR/lib/libGL.so.1" \
      "$OUT_DIR/lib/libvulkan.so.1"
    do
      [ -e "$f" ] || continue
      echo "=== $f ==="
      $READELF -h "$f" | sed -n '1,20p'
      echo "--- NEEDED ---"
      $READELF -d "$f" | grep NEEDED || true
      echo
    done
    if command -v arm-linux-gnueabihf-objdump >/dev/null 2>&1; then
      echo "=== SDIV/UDIV in Xorg/fbdev (Cortex-A9 must have none) ==="
      arm-linux-gnueabihf-objdump -d \
        "$OUT_DIR/lib/xorg/Xorg" \
        "$OUT_DIR/lib/xorg/modules/drivers/fbdev_drv.so" 2>/dev/null \
        | grep -E '[[:space:]](sdiv|udiv)[[:space:]]' | head || echo "NO_SDIV_UDIV_IN_XORG_FBDEV"
    fi
  } | tee "$OUT_DIR/ELF_NOTES.txt"
fi

[ -x "$OUT_DIR/lib/xorg/Xorg" ] || [ -x "$OUT_DIR/bin/Xorg" ] || {
  echo "Xorg binary missing from extract" >&2
  exit 1
}
[ -f "$OUT_DIR/lib/xorg/modules/drivers/fbdev_drv.so" ] || {
  echo "fbdev_drv.so missing from extract" >&2
  exit 1
}
[ -e "$OUT_DIR/lib/libX11.so.6" ] || {
  echo "libX11.so.6 SONAME missing" >&2
  exit 1
}
[ -e "$OUT_DIR/lib/libGL.so.1" ] || {
  echo "libGL.so.1 SONAME missing" >&2
  exit 1
}

log "Xorg modules:"
find "$OUT_DIR/lib/xorg/modules" -type f | sort
log "libs:"
ls -la "$OUT_DIR/lib" | head -80

TAR_DIR=$(dirname "$OUT_DIR")
TAR_BASE=$(basename "$OUT_DIR")
export COPYFILE_DISABLE=1
if tar --version 2>/dev/null | grep -q GNU; then
  tar --owner=root --group=root -C "$TAR_DIR" -cJf "$OUT_TAR" "$TAR_BASE"
else
  tar -C "$TAR_DIR" -cJf "$OUT_TAR" "$TAR_BASE"
fi
ls -lh "$OUT_TAR"
log "DONE"
