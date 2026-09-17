#!/bin/sh
# Launch original Win95 SimCity 2000 (C:\SC2K\SIMCITY.EXE) on the EXISTING
# WinEXE stack. Restarts only the ARM presenter (30 Hz + skip). No FPGA/Xorg.
set -e
WIN=/media/fat/Windows
EXE="$WIN/wineprefix-prebuilt/drive_c/SC2K/SIMCITY.EXE"

CORE=$(cat /tmp/CORENAME 2>/dev/null || true)
[ "$CORE" = "WinEXE_Test" ] || { echo "core is '$CORE', need WinEXE_Test" >&2; exit 1; }
[ -S /tmp/.X11-unix/X0 ] || { echo "dummy Xorg :0 not running" >&2; exit 1; }
[ -f "$EXE" ] || { echo "missing $EXE" >&2; exit 1; }

"$WIN/bin/ss1-mount-prefix.sh"
export WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
"$WIN/bin/ss1-winexe-stop-wine.sh"
# SC2K profile: 30 Hz, skip unchanged, 32x32 dirty spans. HDMI/X stay 60.
if [ -x "$WIN/bin/ss1-winexe-present-restart.sh" ]; then
  SS1_HZ="${SS1_HZ:-30}" SS1_SKIP_UNCHANGED="${SS1_SKIP_UNCHANGED:-1}" \
    SS1_DIRTY="${SS1_DIRTY:-1}" SS1_TILE_W="${SS1_TILE_W:-32}" SS1_TILE_H="${SS1_TILE_H:-32}" \
    "$WIN/bin/ss1-winexe-present-restart.sh"
fi
# Installer registry (SETUP.INS), not sc2kfix / SETUP.EXE.
[ -x "$WIN/bin/ss1-winexe-sc2k-config.sh" ] && "$WIN/bin/ss1-winexe-sc2k-config.sh" || true

export DISPLAY=:0
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err,+loaddll}"
. "$WIN/bin/ss1-x11-env.sh"

[ -x "$WIN/bin/ss1-winexe-ungrab-input.sh" ] && "$WIN/bin/ss1-winexe-ungrab-input.sh" || true
[ -x "$WIN/bin/ss1-winexe-keep-input.sh" ] && "$WIN/bin/ss1-winexe-keep-input.sh" watch || true

LOGDIR="$WIN/logs"
mkdir -p "$LOGDIR"
WINELOG="$LOGDIR/wine-winexe-simcity.log"
: > "$WINELOG"

# Launch from the game directory so relative data/saves resolve.
# SS1_SC2K_NO_EXPLORER=1 skips explorer /desktop. A/B 2026-09-17: dummy X
# has no WM, so dialogs/focus break (256-color OK unusable). Keep Explorer.
if [ "${SS1_SC2K_NO_EXPLORER:-0}" = 1 ]; then
  setsid /bin/sh -c "cd /media/fat/Windows/wineprefix-prebuilt/drive_c/SC2K && exec $WIN/bin/wine C:\\\\SC2K\\\\SIMCITY.EXE" \
    </dev/null >>"$WINELOG" 2>&1 &
else
  setsid /bin/sh -c "cd /media/fat/Windows/wineprefix-prebuilt/drive_c/SC2K && exec $WIN/bin/wine explorer /desktop=ss1,640x480 C:\\\\SC2K\\\\SIMCITY.EXE" \
    </dev/null >>"$WINELOG" 2>&1 &
fi
echo $! > /tmp/ss1-wine.pid
echo "LAUNCHED core=$CORE wine=$(cat /tmp/ss1-wine.pid) exe=C:\\SC2K\\SIMCITY.EXE explorer=$([ "${SS1_SC2K_NO_EXPLORER:-0}" = 1 ] && echo no || echo yes)"
echo "log=$WINELOG"
