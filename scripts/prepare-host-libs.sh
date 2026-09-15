#!/usr/bin/env bash
# Build a relocatable Debian Bullseye armhf host-lib bundle for SuperStation One.
# Extracts packages; does not compile. Intended for GitHub Actions (x86_64).
set -euo pipefail

OUT_DIR="${OUT_DIR:-$(pwd)/host-libs}"
WORKDIR="${WORKDIR:-$(pwd)/.host-libs-work}"
OUT_TAR="${OUT_TAR:-$(pwd)/host-libs.tar.xz}"

# Pinned Debian Bullseye-era armhf debs (glibc 2.31) via snapshot.debian.org.
PACKAGE_URLS=(
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/f/fontconfig/libfontconfig1_2.13.1-4.2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/f/fontconfig/fontconfig-config_2.13.1-4.2_all.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/f/fontconfig/fontconfig_2.13.1-4.2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20210223T211250Z/pool/main/e/expat/libexpat1_2.2.10-2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/u/util-linux/libuuid1_2.36.1-8+deb11u1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220702T033910Z/pool/main/f/freetype/libfreetype6_2.10.4%2Bdfsg-1%2Bdeb11u1_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/libp/libpng1.6/libpng16-16_1.6.37-3_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/b/brotli/libbrotli1_1.0.9-2+b2_armhf.deb"
  "https://snapshot.debian.org/archive/debian/20220419T021707Z/pool/main/z/zlib/zlib1g_1.2.11.dfsg-2+deb11u1_armhf.deb"
)

log() { printf '%s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd wget
require_cmd dpkg-deb
require_cmd tar
require_cmd xz
require_cmd find

rm -rf "$WORKDIR" "$OUT_DIR"
mkdir -p "$WORKDIR/debs" "$WORKDIR/extract" "$OUT_DIR/lib" "$OUT_DIR/etc/fonts" "$OUT_DIR/share/fonts" "$OUT_DIR/bin" "$OUT_DIR/cache"

for url in "${PACKAGE_URLS[@]}"; do
  base=$(basename "${url%%\?*}")
  log "Downloading $base"
  wget -q -O "$WORKDIR/debs/$base" "$url"
  dpkg-deb -x "$WORKDIR/debs/$base" "$WORKDIR/extract"
done

# Flatten shared libraries into lib/, including SONAME symlinks (libfoo.so.1).
for dir in \
  "$WORKDIR/extract/usr/lib/arm-linux-gnueabihf" \
  "$WORKDIR/extract/lib/arm-linux-gnueabihf" \
  "$WORKDIR/extract/usr/lib"
do
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 \( -name 'lib*.so*' -o -name '*.so' \) -exec cp -a {} "$OUT_DIR/lib/" \;
  fi
done
# If a deb only stored the real file, invent the usual SONAME link.
(
  cd "$OUT_DIR/lib"
  for real in lib*.so.[0-9]*.[0-9]*; do
    [ -e "$real" ] || continue
    soname=$(echo "$real" | sed -E 's/(\.so\.[0-9]+)\..*/\1/')
    [ -e "$soname" ] || ln -sf "$real" "$soname"
  done
)

# fc-list / fc-cache for a simple on-device init test
if [ -x "$WORKDIR/extract/usr/bin/fc-list" ]; then
  cp -a "$WORKDIR/extract/usr/bin/fc-list" "$OUT_DIR/bin/"
fi
if [ -x "$WORKDIR/extract/usr/bin/fc-cache" ]; then
  cp -a "$WORKDIR/extract/usr/bin/fc-cache" "$OUT_DIR/bin/"
fi

# Relocatable fontconfig config. Wine/Box86 only need the .so to dlopen;
# a minimal fonts.conf avoids looking in /etc/fonts on the SuperStation.
cat > "$OUT_DIR/etc/fonts/fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir prefix="default">/media/fat/Windows/host-libs/share/fonts</dir>
  <cachedir>/media/fat/Windows/host-libs/cache</cachedir>
  <match target="pattern">
    <edit name="family" mode="append" binding="weak">
      <string>sans-serif</string>
    </edit>
  </match>
</fontconfig>
EOF

# Optional: copy any DejaVu/bitmaps if a fonts package was extracted later
if [ -d "$WORKDIR/extract/usr/share/fonts" ]; then
  cp -a "$WORKDIR/extract/usr/share/fonts/." "$OUT_DIR/share/fonts/" || true
fi

# Tiny placeholder so fontconfig has a fonts dir even without a TTF package
mkdir -p "$OUT_DIR/share/fonts/truetype"

cat > "$OUT_DIR/HOST_LIBS_MANIFEST.txt" <<EOF
purpose=relocatable ARMHF host libs for SuperStation One Box86/Wine
debian_snapshot=pinned Bullseye armhf URLs in scripts/prepare-host-libs.sh
arch=armhf
glibc_target=2.31
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
packages=${PACKAGE_URLS[*]}
notes=Set LD_LIBRARY_PATH to $OUT_DIR/lib and FONTCONFIG_FILE to etc/fonts/fonts.conf
EOF

# Record ELF notes if a cross readelf exists
if command -v arm-linux-gnueabihf-readelf >/dev/null 2>&1; then
  READELF=arm-linux-gnueabihf-readelf
elif command -v readelf >/dev/null 2>&1; then
  READELF=readelf
else
  READELF=
fi

if [ -n "$READELF" ]; then
  {
    echo "=== libfontconfig.so.1 ==="
    $READELF -h "$OUT_DIR/lib/libfontconfig.so.1" || $READELF -h "$OUT_DIR/lib/"libfontconfig.so.1.*
    echo "=== NEEDED ==="
    $READELF -d "$OUT_DIR/lib"/libfontconfig.so.1* 2>/dev/null | grep NEEDED || true
    echo "=== GLIBC ==="
    $READELF -V "$OUT_DIR/lib"/libfontconfig.so.1* 2>/dev/null | grep GLIBC_ | sort -u || true
    echo "=== SDIV/UDIV (objdump if present) ==="
    if command -v arm-linux-gnueabihf-objdump >/dev/null 2>&1; then
      arm-linux-gnueabihf-objdump -d "$OUT_DIR/lib"/libfontconfig.so.1* 2>/dev/null \
        | grep -E '[[:space:]](sdiv|udiv)[[:space:]]' | head || echo "NO_SDIV_UDIV_IN_FONTCONFIG"
    fi
  } | tee "$OUT_DIR/ELF_NOTES.txt"
fi

ls -la "$OUT_DIR/lib"
tar --owner=root --group=root -C "$(dirname "$OUT_DIR")" -cJf "$OUT_TAR" "$(basename "$OUT_DIR")"
ls -lh "$OUT_TAR"
log "DONE"
