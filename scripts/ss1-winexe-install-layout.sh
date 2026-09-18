#!/bin/sh
# Install the public WinEXE ARM layout onto a SuperStation tree.
# Does not copy Wine, Box86, game EXEs, or an RBF.
#
#   ss1-winexe-install-layout.sh [/media/fat]
set -e
ROOT="${1:-/media/fat}"
WIN="$ROOT/Windows"
REPO=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
LIST="$REPO/release/runtime-files.list"

mkdir -p \
  "$WIN/bin" \
  "$WIN/profiles/experimental" \
  "$WIN/runtime" \
  "$WIN/apps" \
  "$WIN/helpers" \
  "$WIN/logs" \
  "$ROOT/games/WinEXE" \
  "$ROOT/_Computer" \
  "$ROOT/_Console"

if [ ! -f "$LIST" ]; then
  echo "missing $LIST" >&2
  exit 1
fi

while IFS= read -r name || [ -n "$name" ]; do
  case "$name" in
    ''|\#*) continue ;;
  esac
  src="$REPO/scripts/$name"
  if [ ! -f "$src" ]; then
    echo "missing runtime file: $src" >&2
    exit 1
  fi
  cp -f "$src" "$WIN/bin/"
done < "$LIST"
chmod +x "$WIN"/bin/ss1-winexe-*.sh "$WIN"/bin/ss1-x11-env.sh \
  "$WIN"/bin/ss1-xorg.sh "$WIN"/bin/ss1-mount-prefix.sh \
  "$WIN"/bin/ss1-cnc-*.sh 2>/dev/null || true

# Project-built helpers (CI artifacts). Never game/Microsoft binaries.
for bin in \
  ss1-winexe-x11-present \
  ss1-winexe-present \
  ss1-pal8-map.so \
  ss1-civ2-cdaudio.so
do
  if [ -f "$REPO/$bin" ]; then
    cp -f "$REPO/$bin" "$WIN/bin/"
  elif [ -f "$REPO/scripts/$bin" ]; then
    cp -f "$REPO/scripts/$bin" "$WIN/bin/"
  fi
done
if [ -f "$REPO/dummy_drv.so" ]; then
  mkdir -p "$WIN/x11/lib/xorg/modules/drivers"
  cp -f "$REPO/dummy_drv.so" "$WIN/x11/lib/xorg/modules/drivers/"
fi
if [ -f "$REPO/ss1-cnc-pal8.exe" ] || [ -f "$REPO/scripts/ss1-cnc-pal8.exe" ]; then
  mkdir -p "$WIN/apps/diag"
  cp -f "$REPO/ss1-cnc-pal8.exe" "$WIN/apps/diag/" 2>/dev/null || true
  cp -f "$REPO/scripts/ss1-cnc-pal8.exe" "$WIN/apps/diag/" 2>/dev/null || true
  cp -f "$REPO/ss1-cnc-pal8.dll" "$WIN/apps/diag/" 2>/dev/null || true
  cp -f "$REPO/scripts/ss1-cnc-pal8.dll" "$WIN/apps/diag/" 2>/dev/null || true
fi
if [ -f "$REPO/scripts/ss1-cnc-capslie.exe" ]; then
  mkdir -p "$WIN/apps/diag"
  cp -f "$REPO/scripts/ss1-cnc-capslie.exe" "$WIN/apps/diag/"
fi

cp -f "$REPO"/profiles/*.ini "$WIN/profiles/"
mkdir -p "$WIN/profiles/experimental"
cp -f "$REPO"/profiles/experimental/*.ini "$WIN/profiles/experimental/" 2>/dev/null || true
cp -f "$REPO"/profiles/README.md "$WIN/profiles/" 2>/dev/null || true
cp -f "$REPO"/apps/README.md "$WIN/apps/" 2>/dev/null || true

if [ -d "$REPO/wex" ]; then
  mkdir -p "$ROOT/games/WinEXE"
  cp -f "$REPO"/wex/*.wex "$ROOT/games/WinEXE/"
  cp -f "$REPO"/wex/README.md "$ROOT/games/WinEXE/" 2>/dev/null || true
fi

if [ -f "$REPO/mister/WinEXE.ini" ]; then
  cp -f "$REPO/mister/WinEXE.ini" "$ROOT/WinEXE.ini"
  if [ -f "$ROOT/MiSTer.ini" ] && ! grep -q '^\[WinEXE\]' "$ROOT/MiSTer.ini"; then
    printf '\n' >> "$ROOT/MiSTer.ini"
    cat "$REPO/mister/WinEXE.ini" >> "$ROOT/MiSTer.ini"
    echo "appended [WinEXE] sections to $ROOT/MiSTer.ini"
  elif [ -f "$ROOT/MiSTer.ini" ]; then
    echo "[WinEXE] already present in $ROOT/MiSTer.ini"
  fi
fi

for doc in README.md LICENSE COPYING THIRD_PARTY_NOTICES.md VERSION \
  docs/APPS.md docs/KNOWN_ISSUES.md docs/RELEASE_NOTES_v0.1.0-beta.md
do
  if [ -f "$REPO/$doc" ]; then
    mkdir -p "$WIN/docs"
    dest="$WIN/docs/$(basename "$doc")"
    case "$doc" in
      docs/*) dest="$WIN/$doc" ;;
      README.md|LICENSE|COPYING|THIRD_PARTY_NOTICES.md|VERSION)
        dest="$WIN/$doc"
        ;;
    esac
    mkdir -p "$(dirname "$dest")"
    cp -f "$REPO/$doc" "$dest"
  fi
done

if [ -x "$WIN/bin/ss1-winexe-check-layout.sh" ]; then
  "$WIN/bin/ss1-winexe-check-layout.sh" "$ROOT" || true
fi

echo "installed WinEXE layout under $WIN"
echo "profiles:"
ls -1 "$WIN/profiles"/*.ini
echo "WEX launchers:"
ls -1 "$ROOT/games/WinEXE"/*.wex 2>/dev/null || true
echo "next: copy WinEXE.rbf to $ROOT/_Computer/WinEXE.rbf and load WinEXE"
