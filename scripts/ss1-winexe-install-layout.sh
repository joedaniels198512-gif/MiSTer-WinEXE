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
  "$ROOT/_Computer" \
  "$ROOT/_Console"

cp -f "$REPO"/scripts/ss1-winexe-*.sh "$WIN/bin/" 2>/dev/null || true
cp -f "$REPO"/scripts/ss1-winexe-*.reg "$WIN/bin/" 2>/dev/null || true
chmod +x "$WIN"/bin/ss1-winexe-*.sh 2>/dev/null || true

cp -f "$REPO"/profiles/*.ini "$WIN/profiles/"
mkdir -p "$WIN/profiles/experimental"
cp -f "$REPO"/profiles/experimental/*.ini "$WIN/profiles/experimental/" 2>/dev/null || true
cp -f "$REPO"/profiles/README.md "$WIN/profiles/" 2>/dev/null || true

if [ -f "$REPO/mister/WinEXE.ini" ]; then
  cp -f "$REPO/mister/WinEXE.ini" "$ROOT/WinEXE.ini"
fi

echo "installed ARM layout under $WIN"
echo "profiles:" 
ls -1 "$WIN/profiles"/*.ini
echo "next: load WinEXE.rbf from the MiSTer menu (FPGA build not started)"
