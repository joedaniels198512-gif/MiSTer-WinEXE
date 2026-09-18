#!/bin/sh
# Machine-readable sanity check for an installed or staged WinEXE tree.
#   ss1-winexe-check-layout.sh [/media/fat]
set -e
ROOT="${1:-/media/fat}"
WIN="$ROOT/Windows"
fail=0
need() {
  if [ ! -e "$1" ]; then
    echo "MISSING $1"
    fail=1
  fi
}

need "$WIN/bin/ss1-winexe-launch.sh"
need "$WIN/bin/ss1-winexe-xorg.sh"
need "$WIN/bin/ss1-winexe-present-restart.sh"
need "$WIN/bin/ss1-winexe-stop-wine.sh"
need "$WIN/bin/ss1-winexe-keep-input.sh"
need "$WIN/bin/ss1-winexe-ungrab-input.sh"
need "$WIN/bin/ss1-x11-env.sh"
need "$WIN/bin/xorg.winexe.conf"
need "$WIN/bin/ss1-winexe-cnc-cd.sh"
need "$WIN/bin/ss1-cnc-pal8.sh"
need "$WIN/bin/ss1-winexe-civ2-cd.sh"
need "$WIN/bin/ss1-winexe-civ2-cdaudio.sh"
need "$WIN/bin/ss1-winexe-sc2k-config.sh"
need "$WIN/bin/ss1-winexe-winamp-config.sh"
need "$WIN/bin/ss1-winexe-freecell-deal.sh"
need "$WIN/profiles/notepad.ini"
need "$WIN/profiles/cnc.ini"
need "$WIN/profiles/civ2.ini"
need "$ROOT/games/WinEXE/Notepad.wex"
need "$ROOT/games/WinEXE/Civilization II.wex"

# Companion binaries: warn only (CI / previous device may supply them).
for opt in \
  "$WIN/bin/ss1-winexe-x11-present" \
  "$WIN/bin/ss1-pal8-map.so" \
  "$WIN/bin/ss1-civ2-cdaudio.so" \
  "$WIN/x11/lib/xorg/modules/drivers/dummy_drv.so"
do
  if [ ! -e "$opt" ]; then
    echo "OPTIONAL_MISSING $opt"
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "LAYOUT_FAIL"
  exit 1
fi
echo "LAYOUT_OK root=$ROOT"
exit 0
