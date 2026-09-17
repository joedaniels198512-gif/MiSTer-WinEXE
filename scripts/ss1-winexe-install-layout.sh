#!/bin/sh
# Copy ARM-side WinEXE core files onto a SuperStation tree.
# Does not copy Wine, Box86, EXEs, or an RBF. Does not start Quartus.
#
#   ss1-winexe-install-layout.sh [/media/fat]
set -e
ROOT="${1:-/media/fat}"
WIN="$ROOT/Windows"
REPO=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

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

cp -f "$REPO"/scripts/ss1-winexe-*.sh "$WIN/bin/" 2>/dev/null || true
cp -f "$REPO"/scripts/ss1-winexe-*.reg "$WIN/bin/" 2>/dev/null || true
chmod +x "$WIN"/bin/ss1-winexe-*.sh 2>/dev/null || true

cp -f "$REPO"/profiles/*.ini "$WIN/profiles/"
mkdir -p "$WIN/profiles/experimental"
cp -f "$REPO"/profiles/experimental/*.ini "$WIN/profiles/experimental/" 2>/dev/null || true
cp -f "$REPO"/profiles/README.md "$WIN/profiles/" 2>/dev/null || true

if [ -d "$REPO/wex" ]; then
  mkdir -p "$ROOT/games/WinEXE"
  cp -f "$REPO"/wex/*.wex "$ROOT/games/WinEXE/" 2>/dev/null || true
  cp -f "$REPO"/wex/README.md "$ROOT/games/WinEXE/" 2>/dev/null || true
fi

if [ -f "$REPO/mister/WinEXE.ini" ]; then
  cp -f "$REPO/mister/WinEXE.ini" "$ROOT/WinEXE.ini"
  # Main only reads MiSTer.ini sections, not the standalone fragment.
  if [ -f "$ROOT/MiSTer.ini" ] && ! grep -q '^\[WinEXE\]' "$ROOT/MiSTer.ini"; then
    printf '\n' >> "$ROOT/MiSTer.ini"
    cat "$REPO/mister/WinEXE.ini" >> "$ROOT/MiSTer.ini"
    echo "appended [WinEXE] sections to $ROOT/MiSTer.ini"
  elif [ -f "$ROOT/MiSTer.ini" ]; then
    echo "[WinEXE] already present in $ROOT/MiSTer.ini"
  fi
fi

echo "installed ARM layout under $WIN"
echo "profiles:" 
ls -1 "$WIN/profiles"/*.ini
echo "WEX launchers:"
ls -1 "$ROOT/games/WinEXE"/*.wex 2>/dev/null || true
echo "next: load WinEXE.rbf and use Load Application..."
