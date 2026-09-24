#!/bin/sh
# Assemble a FAT-rooted WinEXE-v0.1.0-beta.zip.
# Archive root is the MiSTer SD root: _Computer/, Scripts/, docs/, games/.
set -eu
ROOT=$(CDPATH= cd "${1:-$(dirname "$0")/..}" && pwd)
VER=$(tr -d ' \n' < "$ROOT/VERSION")
NAME="WinEXE-v${VER}"
OUT="${2:-$ROOT/dist/${NAME}.zip}"
STAGE="${TMPDIR:-/tmp}/${NAME}.stage.$$"
ART="${ARTIFACT_DIR:-$ROOT/artifacts}"
WINEXE="games/WinEXE"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$(dirname "$OUT")"

copy() {
  src=$1
  dest=$2
  mkdir -p "$(dirname "$STAGE/$dest")"
  cp -R "$src" "$STAGE/$dest"
}

pick() {
  for p in "$@"; do
    if [ -f "$p" ]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

# User-facing docs only. No developer FPGA/WMP notes at the SD root.
mkdir -p "$STAGE/docs/WinEXE"
cp -f "$ROOT/README.md" "$STAGE/docs/WinEXE/README.md"
cp -f "$ROOT/docs/APPS.md" "$STAGE/docs/WinEXE/APPS.md"
cp -f "$ROOT/docs/KNOWN_ISSUES.md" "$STAGE/docs/WinEXE/KNOWN_ISSUES.md"
cp -f "$ROOT/LICENSE" "$STAGE/docs/WinEXE/LICENSE"
cp -f "$ROOT/COPYING" "$STAGE/docs/WinEXE/COPYING"
cp -f "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/docs/WinEXE/THIRD_PARTY_NOTICES.md"
cp -f "$ROOT/mister/WinEXE.ini" "$STAGE/docs/WinEXE/WinEXE.ini"

mkdir -p "$STAGE/Scripts"
INSTALLER=""
for cand in "$ROOT/Scripts/WinEXE Installer.sh" "$ROOT/scripts/WinEXE Installer.sh"; do
  [ -f "$cand" ] && INSTALLER=$cand && break
done
[ -n "$INSTALLER" ] || { echo "missing WinEXE Installer.sh" >&2; rm -rf "$STAGE"; exit 1; }
cp -f "$INSTALLER" "$STAGE/Scripts/WinEXE Installer.sh"
chmod +x "$STAGE/Scripts/WinEXE Installer.sh"

mkdir -p "$STAGE/$WINEXE/profiles/experimental" "$STAGE/$WINEXE/bin" \
  "$STAGE/$WINEXE/apps" "$STAGE/$WINEXE/logs" "$STAGE/$WINEXE/iso"
cp -f "$ROOT"/profiles/*.ini "$STAGE/$WINEXE/profiles/"
cp -f "$ROOT"/profiles/experimental/*.ini "$STAGE/$WINEXE/profiles/experimental/" 2>/dev/null || true
cp -f "$ROOT/apps/README.md" "$STAGE/$WINEXE/apps/"
cp -f "$ROOT"/wex/*.wex "$STAGE/$WINEXE/"

while IFS= read -r name || [ -n "$name" ]; do
  case "$name" in ''|\#*) continue ;; esac
  cp -f "$ROOT/scripts/$name" "$STAGE/$WINEXE/bin/"
done < "$ROOT/release/runtime-files.list"
chmod +x "$STAGE/$WINEXE"/bin/* 2>/dev/null || true

# FPGA core: dated MiSTer name from the artifact mtime (or today).
if RBF=$(pick \
  "$ART/gha-latest/fpga/WinEXE.rbf/WinEXE.rbf" \
  "$ART/winexe-gha/WinEXE.rbf/WinEXE.rbf" \
  "$ART/WinEXE.rbf"); then
  RBF_DATE=$(date -u -r "$RBF" +%Y%m%d 2>/dev/null || date -u +%Y%m%d)
  mkdir -p "$STAGE/_Computer"
  cp -f "$RBF" "$STAGE/_Computer/WinEXE_${RBF_DATE}.rbf"
fi

# Custom Main — SD root only (main=MiSTer_WinEXE).
# Refuse a missing or stale binary so an old Windows-path Main cannot slip in.
if ! MAIN=$(pick \
  "$ART/gha-latest/main/MiSTer_WinEXE/MiSTer_WinEXE" \
  "$ART/MiSTer_WinEXE"); then
  echo "MiSTer_WinEXE missing under $ART" >&2
  rm -rf "$STAGE"
  exit 1
fi
if command -v strings >/dev/null 2>&1; then
  if ! strings "$MAIN" | grep -q '/media/fat/games/WinEXE/bin/ss1-winexe-launch.sh'; then
    echo "refusing $MAIN: does not launch games/WinEXE" >&2
    rm -rf "$STAGE"
    exit 1
  fi
  if strings "$MAIN" | grep -q '/media/fat/Windows/bin/ss1-winexe-launch.sh'; then
    echo "refusing $MAIN: still hardcodes /media/fat/Windows" >&2
    rm -rf "$STAGE"
    exit 1
  fi
fi
cp -f "$MAIN" "$STAGE/MiSTer_WinEXE"
chmod +x "$STAGE/MiSTer_WinEXE"

if PRES=$(pick \
  "$ART/gha-latest/presenter/ss1-winexe-x11-present/ss1-winexe-x11-present" \
  "$ART/winexe-presenter/ss1-winexe-x11-present/ss1-winexe-x11-present"); then
  cp -f "$PRES" "$STAGE/$WINEXE/bin/ss1-winexe-x11-present"
  chmod +x "$STAGE/$WINEXE/bin/ss1-winexe-x11-present"
fi
DUM=$(pick \
  "$ART/gha-latest/presenter/dummy_drv.so/dummy_drv.so" \
  "$ART/winexe-presenter/dummy_drv.so/dummy_drv.so" || true)

# PAL8 map used by the C&C helper. Do not pack unused guest PE diagnostics.
if SO=$(pick "$ART/gha-latest/fpga/ss1-pal8-map.so/ss1-pal8-map.so" "$ART/ss1-pal8-map.so"); then
  cp -f "$SO" "$STAGE/$WINEXE/bin/ss1-pal8-map.so"
fi

if [ -x "$ART/wine-devel/extract/opt/wine-devel/bin/wine" ]; then
  mkdir -p "$STAGE/$WINEXE/wine-installer/opt"
  cp -a "$ART/wine-devel/extract/opt/wine-devel" "$STAGE/$WINEXE/wine-installer/opt/"
fi

if TAR=$(pick \
  "$ART/gha-latest/prefix/wineprefix-prebuilt/wineprefix-prebuilt.tar.xz" \
  "$ART/wineprefix-prebuilt/wineprefix-prebuilt.tar.xz"); then
  cp -f "$TAR" "$STAGE/$WINEXE/wineprefix-prebuilt.tar.xz"
fi

if [ -f "$ART/x11-runtime/x11-runtime.tar.xz" ]; then
  tar -C "$STAGE/$WINEXE" -xJf "$ART/x11-runtime/x11-runtime.tar.xz"
  if [ ! -d "$STAGE/$WINEXE/x11" ] && [ -d "$STAGE/$WINEXE/x11-runtime" ]; then
    mv "$STAGE/$WINEXE/x11-runtime" "$STAGE/$WINEXE/x11"
  fi
fi
if [ -n "${DUM:-}" ] && [ -f "$DUM" ]; then
  mkdir -p "$STAGE/$WINEXE/x11/lib/xorg/modules/drivers"
  cp -f "$DUM" "$STAGE/$WINEXE/x11/lib/xorg/modules/drivers/dummy_drv.so"
fi
if [ -f "$STAGE/$WINEXE/bin/xorg.winexe.conf" ]; then
  mkdir -p "$STAGE/$WINEXE/x11/etc/X11"
  cp -f "$STAGE/$WINEXE/bin/xorg.winexe.conf" "$STAGE/$WINEXE/x11/etc/X11/xorg.winexe.conf"
fi
if [ -f "$ART/host-libs/host-libs.tar.xz" ]; then
  tar -C "$STAGE/$WINEXE" -xJf "$ART/host-libs/host-libs.tar.xz"
fi

if BOX=$(pick \
  "$ART/box86-ss1/box86" \
  "$ART/box86-ss1/extract/usr/local/bin/box86" \
  "$ART/box86"); then
  mkdir -p "$STAGE/$WINEXE/box86-ss1"
  cp -f "$BOX" "$STAGE/$WINEXE/box86-ss1/box86"
  chmod +x "$STAGE/$WINEXE/box86-ss1/box86"
  if [ -f "$ART/box86-ss1/extract/usr/share/doc/box86-generic-arm/LICENSE" ]; then
    cp -f "$ART/box86-ss1/extract/usr/share/doc/box86-generic-arm/LICENSE" \
      "$STAGE/$WINEXE/box86-ss1/LICENSE"
  fi
  if [ -f "$ART/box86-ss1/SOURCE.txt" ]; then
    cp -f "$ART/box86-ss1/SOURCE.txt" "$STAGE/$WINEXE/box86-ss1/SOURCE.txt"
  fi
fi
if [ -d "$ART/box86-ss1/extract/usr/lib/box86-i386-linux-gnu" ]; then
  mkdir -p "$STAGE/$WINEXE/box86-extracted/usr/lib"
  cp -a "$ART/box86-ss1/extract/usr/lib/box86-i386-linux-gnu" \
    "$STAGE/$WINEXE/box86-extracted/usr/lib/"
fi
if [ -f "$ART/box86-ss1/extract/etc/box86.box86rc" ]; then
  mkdir -p "$STAGE/$WINEXE/box86-ss1"
  cp -f "$ART/box86-ss1/extract/etc/box86.box86rc" \
    "$STAGE/$WINEXE/box86-ss1/box86.box86rc"
fi

# Refuse media, dumps, VCS, editor, and macOS metadata
if find "$STAGE" -type f | grep -qiE '\.(iso|cue|rom|avi|wav|mp3|wma|sav)$'; then
  echo "refusing to pack media/disc images" >&2
  rm -rf "$STAGE"
  exit 1
fi
if find "$STAGE" -type f | grep -qiE '\.(png|bgra|fb|raw)$'; then
  echo "refusing to pack framebuffer dumps" >&2
  rm -rf "$STAGE"
  exit 1
fi
find "$STAGE" \( -name '.DS_Store' -o -name '._*' -o -name '.git' -o -name '__MACOSX' \) -prune -exec rm -rf {} + 2>/dev/null || true

# No wrapper directory. FAT-root zip. Strip Apple extra fields.
rm -f "$OUT"
(
  CDPATH= cd "$STAGE"
  COPYFILE_DISABLE=1 zip -Xqr "$OUT" .
)
rm -rf "$STAGE"
echo "WROTE $OUT"
ls -l "$OUT"
