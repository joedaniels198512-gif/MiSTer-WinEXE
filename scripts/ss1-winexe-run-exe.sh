#!/bin/sh
# Launch an apps/*.exe on the EXISTING WinEXE stack (dummy Xorg + presenter +
# WinEXE_Test). Does not load a core, restart Xorg, or change the presenter.
set -e
WIN=/media/fat/Windows
APPS="$WIN/apps"
EXE=${1:-mspaint.exe}
case "$EXE" in
  /*) ;;
  *) EXE="$APPS/$EXE" ;;
esac
[ -f "$EXE" ] || { echo "missing $EXE" >&2; exit 1; }

CORE=$(cat /tmp/CORENAME 2>/dev/null || true)
[ "$CORE" = "WinEXE_Test" ] || { echo "core is '$CORE', need WinEXE_Test" >&2; exit 1; }
[ -S /tmp/.X11-unix/X0 ] || { echo "dummy Xorg :0 not running" >&2; exit 1; }
[ -f /tmp/ss1-winexe-x11-present.pid ] && kill -0 "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null \
  || { echo "ss1-winexe-x11-present not running" >&2; exit 1; }

"$WIN/bin/ss1-mount-prefix.sh"
export WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
"$WIN/bin/ss1-winexe-stop-wine.sh"
if [ -x "$WIN/bin/ss1-winexe-present-restart.sh" ]; then
  SS1_HZ=60 SS1_SKIP_UNCHANGED=1 SS1_DIRTY=0 "$WIN/bin/ss1-winexe-present-restart.sh" || true
fi
for d in /proc/[0-9]*; do
  c=$(cat "$d/comm" 2>/dev/null) || continue
  case "$c" in
    Xorg|ss1-winexe-x11-*) taskset -p 0x3 "${d#/proc/}" >/dev/null 2>&1 || true ;;
  esac
done

export DISPLAY=:0
export LD_LIBRARY_PATH="$WIN/x11/lib:$WIN/host-libs/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err}"
. "$WIN/bin/ss1-x11-env.sh"

# Main may have re-grabbed USB if the core was reloaded; cheap to re-release.
[ -x "$WIN/bin/ss1-winexe-ungrab-input.sh" ] && "$WIN/bin/ss1-winexe-ungrab-input.sh" || true
[ -x "$WIN/bin/ss1-winexe-keep-input.sh" ] && "$WIN/bin/ss1-winexe-keep-input.sh" watch || true

STEM=$(basename "$EXE" | tr 'A-Z' 'a-z')
STEM=${STEM%.exe}
LOGDIR="$WIN/logs"
mkdir -p "$LOGDIR"
WINELOG="$LOGDIR/wine-winexe-${STEM}.log"
: > "$WINELOG"
setsid /bin/sh -c "exec $WIN/bin/wine explorer /desktop=ss1,640x480 $EXE" \
  </dev/null >>"$WINELOG" 2>&1 &
echo $! > /tmp/ss1-wine.pid
echo "LAUNCHED core=$CORE xorg=$(cat /tmp/ss1-xorg.pid) present=$(cat /tmp/ss1-winexe-x11-present.pid) wine=$(cat /tmp/ss1-wine.pid) exe=$EXE"
echo "log=$WINELOG"
