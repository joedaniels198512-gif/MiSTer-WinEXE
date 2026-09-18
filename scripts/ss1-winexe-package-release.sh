#!/bin/sh
# Assemble WinEXE-v0.1.0-beta.zip — public files only.
# Does not embed Wine, Box86, prefixes, or game binaries.
# Optional: drop WinEXE.rbf / presenter binaries in $ARTIFACT_DIR to include them.
set -eu
ROOT=$(CDPATH= cd "${1:-$(dirname "$0")/..}" && pwd)
VER=$(tr -d ' \n' < "$ROOT/VERSION")
NAME="WinEXE-v${VER}"
OUT="${2:-$ROOT/dist/${NAME}.zip}"
STAGE="${TMPDIR:-/tmp}/${NAME}.stage.$$"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT/artifacts}"

rm -rf "$STAGE"
mkdir -p "$STAGE/$NAME" "$(dirname "$OUT")"

copy() {
  src=$1
  dest=$2
  mkdir -p "$(dirname "$STAGE/$NAME/$dest")"
  cp -R "$src" "$STAGE/$NAME/$dest"
}

copy "$ROOT/README.md" README.md
copy "$ROOT/LICENSE" LICENSE
copy "$ROOT/COPYING" COPYING
copy "$ROOT/THIRD_PARTY_NOTICES.md" THIRD_PARTY_NOTICES.md
copy "$ROOT/VERSION" VERSION
copy "$ROOT/install.sh" install.sh
copy "$ROOT/docs/APPS.md" docs/APPS.md
copy "$ROOT/docs/KNOWN_ISSUES.md" docs/KNOWN_ISSUES.md
copy "$ROOT/docs/RELEASE_NOTES_v0.1.0-beta.md" docs/RELEASE_NOTES_v0.1.0-beta.md
copy "$ROOT/docs/WINEXE_CORE.md" docs/WINEXE_CORE.md
copy "$ROOT/docs/WINEXE_FPGA.md" docs/WINEXE_FPGA.md
copy "$ROOT/docs/X11_RUNTIME.md" docs/X11_RUNTIME.md
copy "$ROOT/docs/WINE_PREFIX.md" docs/WINE_PREFIX.md
copy "$ROOT/docs/HOST_LIBS.md" docs/HOST_LIBS.md
copy "$ROOT/apps/README.md" apps/README.md
copy "$ROOT/profiles" profiles
copy "$ROOT/wex" wex
copy "$ROOT/mister/WinEXE.ini" mister/WinEXE.ini
copy "$ROOT/helpers/README.md" helpers/README.md
copy "$ROOT/release/runtime-files.list" release/runtime-files.list

mkdir -p "$STAGE/$NAME/scripts"
while IFS= read -r name || [ -n "$name" ]; do
  case "$name" in ''|\#*) continue ;; esac
  cp -f "$ROOT/scripts/$name" "$STAGE/$NAME/scripts/"
done < "$ROOT/release/runtime-files.list"
cp -f "$ROOT/scripts/ss1-winexe-package-release.sh" "$STAGE/$NAME/scripts/"
cp -f "$ROOT/scripts/ss1-winexe-release-check.sh" "$STAGE/$NAME/scripts/"
chmod +x "$STAGE/$NAME/install.sh" "$STAGE/$NAME/scripts/"*.sh

# Optional CI binaries (project-built only)
if [ -d "$ARTIFACT_DIR" ]; then
  for f in WinEXE.rbf ss1-winexe-x11-present ss1-pal8-map.so \
    ss1-civ2-cdaudio.so dummy_drv.so ss1-cnc-pal8.dll ss1-cnc-pal8.exe \
    MiSTer_WinEXE
  do
    if [ -f "$ARTIFACT_DIR/$f" ]; then
      case "$f" in
        WinEXE.rbf) cp -f "$ARTIFACT_DIR/$f" "$STAGE/$NAME/WinEXE.rbf" ;;
        dummy_drv.so)
          mkdir -p "$STAGE/$NAME/x11/lib/xorg/modules/drivers"
          cp -f "$ARTIFACT_DIR/$f" "$STAGE/$NAME/x11/lib/xorg/modules/drivers/"
          ;;
        MiSTer_WinEXE) cp -f "$ARTIFACT_DIR/$f" "$STAGE/$NAME/MiSTer_WinEXE" ;;
        *)
          mkdir -p "$STAGE/$NAME/bin"
          cp -f "$ARTIFACT_DIR/$f" "$STAGE/$NAME/bin/"
          ;;
      esac
    fi
  done
fi

# Refuse to pack forbidden extensions from the stage
if find "$STAGE" -type f | grep -qiE '\.(iso|cue|img|rom|avi|wav|mp3|wma|sav)$'; then
  echo "refusing to pack media/disc images" >&2
  rm -rf "$STAGE"
  exit 1
fi
if find "$STAGE" -type d -name tmp -o -type d -name extract -o -type d -name wineprefix-prebuilt | grep -q .; then
  echo "refusing to pack tmp/extract/prefix trees" >&2
  rm -rf "$STAGE"
  exit 1
fi

# zip is gitignored at repo root; write outside or under dist/
rm -f "$OUT"
( CDPATH= cd "$STAGE" && zip -qr "$OUT" "$NAME" )
rm -rf "$STAGE"
echo "WROTE $OUT"
ls -l "$OUT"
