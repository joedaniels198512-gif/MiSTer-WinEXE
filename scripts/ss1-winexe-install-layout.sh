#!/bin/sh
# Install the public WinEXE ARM layout onto a SuperStation tree.
# Does not copy Wine, Box86, game EXEs, or an RBF.
#
#   ss1-winexe-install-layout.sh [/media/fat]
set -e
ROOT="${1:-/media/fat}"
WIN="$ROOT/games/WinEXE"
REPO=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
LIST="$REPO/release/runtime-files.list"

mkdir -p \
  "$WIN/bin" \
  "$WIN/profiles/experimental" \
  "$WIN/apps" \
  "$WIN/logs" \
  "$WIN/iso" \
  "$ROOT/docs/WinEXE" \
  "$ROOT/_Computer"

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
chmod +x "$WIN"/bin/* 2>/dev/null || true

for bin in \
  ss1-winexe-x11-present \
  ss1-pal8-map.so \
  ss1-civ2-cdaudio.so
do
  if [ -f "$REPO/$bin" ]; then
    cp -f "$REPO/$bin" "$WIN/bin/"
  elif [ -f "$REPO/scripts/$bin" ]; then
    cp -f "$REPO/scripts/$bin" "$WIN/bin/"
  fi
done

cp -f "$REPO"/profiles/*.ini "$WIN/profiles/"
mkdir -p "$WIN/profiles/experimental"
cp -f "$REPO"/profiles/experimental/*.ini "$WIN/profiles/experimental/" 2>/dev/null || true
cp -f "$REPO"/apps/README.md "$WIN/apps/" 2>/dev/null || true

if [ -d "$REPO/wex" ]; then
  cp -f "$REPO"/wex/*.wex "$WIN/"
fi

if [ -f "$REPO/mister/WinEXE.ini" ]; then
  cp -f "$REPO/mister/WinEXE.ini" "$ROOT/docs/WinEXE/WinEXE.ini"
  if [ -f "$ROOT/MiSTer.ini" ] && ! grep -q '^\[WinEXE\]' "$ROOT/MiSTer.ini"; then
    printf '\n' >> "$ROOT/MiSTer.ini"
    cat "$REPO/mister/WinEXE.ini" >> "$ROOT/MiSTer.ini"
    echo "appended [WinEXE] sections to $ROOT/MiSTer.ini"
  fi
fi

for doc in README.md LICENSE COPYING THIRD_PARTY_NOTICES.md \
  docs/APPS.md docs/KNOWN_ISSUES.md
do
  if [ -f "$REPO/$doc" ]; then
    cp -f "$REPO/$doc" "$ROOT/docs/WinEXE/$(basename "$doc")"
  fi
done

if [ -x "$WIN/bin/ss1-winexe-check-layout.sh" ]; then
  "$WIN/bin/ss1-winexe-check-layout.sh" "$ROOT" || true
fi

echo "installed WinEXE layout under $WIN"
echo "next: copy WinEXE_YYYYMMDD.rbf to $ROOT/_Computer/ and load WinEXE"
