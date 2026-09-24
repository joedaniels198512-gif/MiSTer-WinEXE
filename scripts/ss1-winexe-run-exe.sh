#!/bin/sh
# Launch an apps/*.exe on the existing WinEXE stack.
# Known EXEs use profiles; anything else still uses the generic 60 Hz path.
set -e
WIN="${WIN:-/media/fat/games/WinEXE}"
LAUNCH="$WIN/bin/ss1-winexe-launch.sh"
[ -x "$LAUNCH" ] || LAUNCH="$(dirname "$0")/ss1-winexe-launch.sh"
APPS="$WIN/apps"
EXE=${1:-mspaint.exe}
BASE=$(basename "$EXE" | tr 'A-Z' 'a-z')
case "$BASE" in
  mspaint.exe|paint.exe)
    exec "$LAUNCH" launch paint
    ;;
  notepad.exe)
    exec "$LAUNCH" launch notepad
    ;;
  winmine.exe)
    exec "$LAUNCH" launch minesweeper
    ;;
  sol.exe)
    exec "$LAUNCH" launch solitaire
    ;;
  freecell.exe)
    exec "$LAUNCH" launch freecell
    ;;
  mshearts.exe|hearts.exe)
    exec "$LAUNCH" launch hearts
    ;;
esac

# Ad-hoc EXE: reuse the paint-class 60 Hz runtime without a dedicated INI.
case "$EXE" in
  /*) ;;
  *) EXE="$APPS/$EXE" ;;
esac
[ -f "$EXE" ] || { echo "missing $EXE" >&2; exit 1; }

CORE=$(cat /tmp/CORENAME 2>/dev/null || true)
case "$CORE" in
  WinEXE|WinEXE_Test) ;;
  *) echo "core is '$CORE', need WinEXE*" >&2; exit 1 ;;
esac
[ -S /tmp/.X11-unix/X0 ] || { echo "dummy Xorg :0 not running" >&2; exit 1; }

"$WIN/bin/ss1-mount-prefix.sh"
export WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
"$WIN/bin/ss1-winexe-stop-wine.sh" || true
"$WIN/bin/ss1-winexe-xorg.sh" start
[ -x "$WIN/bin/ss1-winexe-ungrab-input.sh" ] && "$WIN/bin/ss1-winexe-ungrab-input.sh" || true
[ -x "$WIN/bin/ss1-winexe-keep-input.sh" ] && "$WIN/bin/ss1-winexe-keep-input.sh" watch || true
SS1_HZ=60 SS1_SKIP_UNCHANGED=1 SS1_DIRTY=0 "$WIN/bin/ss1-winexe-present-restart.sh" || true
for d in /proc/[0-9]*; do
  c=$(cat "$d/comm" 2>/dev/null) || continue
  case "$c" in
    Xorg|ss1-winexe-x11-*) taskset -p 0x3 "${d#/proc/}" >/dev/null 2>&1 || true ;;
  esac
done
export DISPLAY=:0
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err}"
. "$WIN/bin/ss1-x11-env.sh"
STEM=$(basename "$EXE" | tr 'A-Z' 'a-z')
STEM=${STEM%.exe}
LOGDIR="$WIN/logs"
mkdir -p "$LOGDIR"
WINELOG="$LOGDIR/wine-winexe-${STEM}.log"
: > "$WINELOG"
setsid /bin/sh -c "exec $WIN/bin/wine explorer /desktop=ss1,640x480 $EXE" \
  </dev/null >>"$WINELOG" 2>&1 &
echo $! > /tmp/ss1-wine.pid
echo "LAUNCHED ad-hoc exe=$EXE wine=$(cat /tmp/ss1-wine.pid) log=$WINELOG"
