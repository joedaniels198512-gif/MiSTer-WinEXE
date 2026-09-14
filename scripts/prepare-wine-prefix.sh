#!/usr/bin/env bash
# Prepare a minimal Wine 7.1 win32 prefix for SuperStation One + Box86.
# Intended to run on a native x86_64/i386 Linux host (GitHub Actions).
# Does not compile Wine. Downloads the same WineHQ 7.1 bullseye i386 debs
# already used on the SuperStation and extracts them.
set -euo pipefail

WINE_VERSION="7.1~bullseye-1"
WINEHQ_I386="https://dl.winehq.org/wine-builds/debian/dists/bullseye/main/binary-i386"
WINE_ROOT="${WINE_ROOT:-/media/fat/Windows/wine-installer/opt/wine-devel}"
WINEPREFIX_PATH="${WINEPREFIX_PATH:-/media/fat/Windows/wineprefix-prebuilt}"
WORKDIR="${WORKDIR:-$(pwd)/.wine-prepare-work}"
OUT_TAR="${OUT_TAR:-$(pwd)/wineprefix-prebuilt.tar.xz}"

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

mkdir -p "$WORKDIR/debs" "$(dirname "$WINE_ROOT")" "$(dirname "$WINEPREFIX_PATH")"

if [ ! -x "$WINE_ROOT/bin/wine" ]; then
  log "Downloading Wine $WINE_VERSION i386 debs (no compile)"
  wget -q -O "$WORKDIR/debs/wine-devel-i386_${WINE_VERSION}_i386.deb" \
    "$WINEHQ_I386/wine-devel-i386_${WINE_VERSION}_i386.deb"
  wget -q -O "$WORKDIR/debs/wine-devel_${WINE_VERSION}_i386.deb" \
    "$WINEHQ_I386/wine-devel_${WINE_VERSION}_i386.deb"
  rm -rf "$WORKDIR/extract"
  mkdir -p "$WORKDIR/extract"
  dpkg-deb -x "$WORKDIR/debs/wine-devel-i386_${WINE_VERSION}_i386.deb" "$WORKDIR/extract"
  dpkg-deb -x "$WORKDIR/debs/wine-devel_${WINE_VERSION}_i386.deb" "$WORKDIR/extract"
  rm -rf "$WINE_ROOT"
  mkdir -p "$(dirname "$WINE_ROOT")"
  mv "$WORKDIR/extract/opt/wine-devel" "$WINE_ROOT"
fi

if [ ! -x "$WINE_ROOT/bin/wine" ]; then
  echo "Wine binary missing after extract: $WINE_ROOT/bin/wine" >&2
  exit 1
fi

"$WINE_ROOT/bin/wine" --version

rm -rf "$WINEPREFIX_PATH"
mkdir -p "$WINEPREFIX_PATH"

export WINEPREFIX="$WINEPREFIX_PATH"
export WINEARCH=win32
export WINELOADER="$WINE_ROOT/bin/wine"
export WINESERVER="$WINE_ROOT/bin/wineserver"
export PATH="$WINE_ROOT/bin:$PATH"
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export WINEDEBUG=-all
unset DISPLAY || true
unset WAYLAND_DISPLAY || true

log "Initialising win32 prefix at $WINEPREFIX_PATH"
if command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a "$WINE_ROOT/bin/wine" wineboot --init
else
  "$WINE_ROOT/bin/wine" wineboot --init
fi
"$WINE_ROOT/bin/wineserver" -w

log "Verifying console on the builder (native x86, not Box86)"
"$WINE_ROOT/bin/wine" cmd /c ver
"$WINE_ROOT/bin/wine" cmd /c echo HELLO FROM WINDOWS ON SUPERSTATION
"$WINE_ROOT/bin/wineserver" -k || true
"$WINE_ROOT/bin/wineserver" -w || true

# Drop caches/temp that are not needed to prove cmd.exe
rm -rf \
  "$WINEPREFIX_PATH/drive_c/users/$USER/Temp" \
  "$WINEPREFIX_PATH/drive_c/windows/temp"/* \
  "$WINEPREFIX_PATH/drive_c/windows/logs" 2>/dev/null || true

cat > "$WINEPREFIX_PATH/PREFIX_MANIFEST.txt" <<EOF
wine_version=wine-$WINE_VERSION
wine_arch=win32
wine_root=$WINE_ROOT
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
purpose=minimal console prefix for SuperStation One Box86
notes=dosdevices and system32 symlinks expect Wine at $WINE_ROOT
EOF

log "Packing $OUT_TAR"
tar -C "$(dirname "$WINEPREFIX_PATH")" -cJf "$OUT_TAR" "$(basename "$WINEPREFIX_PATH")"
ls -lh "$OUT_TAR"
log "Prefix file count: $(find "$WINEPREFIX_PATH" | wc -l)"
log "DONE"
