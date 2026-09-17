#!/bin/sh
# Launch genuine Winamp 2.91 on the EXISTING WinEXE stack.
# Stamps first-run/mini-browser settings, then starts wineserver + winamp.exe.
# Does not load a core, restart Xorg, or change the presenter/input path.
set -e
WIN=/media/fat/Windows
WA="$WIN/wineprefix-prebuilt/drive_c/Program Files/Winamp"
MP3=${1:-}
if [ -z "$MP3" ]; then
  if [ -f "$WIN/wineprefix-prebuilt/drive_c/WA.mp3" ]; then
    MP3="$WIN/wineprefix-prebuilt/drive_c/WA.mp3"
  elif [ -f "$WIN/music/08 In The End.mp3" ]; then
    MP3="$WIN/music/08 In The End.mp3"
  fi
fi

CORE=$(cat /tmp/CORENAME 2>/dev/null || true)
[ "$CORE" = "WinEXE_Test" ] || { echo "core is '$CORE', need WinEXE_Test" >&2; exit 1; }
[ -S /tmp/.X11-unix/X0 ] || { echo "dummy Xorg :0 not running" >&2; exit 1; }
[ -f /tmp/ss1-winexe-x11-present.pid ] && kill -0 "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null \
  || { echo "ss1-winexe-x11-present not running" >&2; exit 1; }
[ -f "$WA/winamp.exe" ] || { echo "missing $WA/winamp.exe" >&2; exit 1; }

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

"$WIN/bin/ss1-winexe-winamp-config.sh"

export DISPLAY=:0
# Keep HTML/Gecko out of the Winamp process. Do not install Wine Gecko.
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mshtml=d;ieframe=d;shdocvw=d"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err}"
. "$WIN/bin/ss1-x11-env.sh"

[ -x "$WIN/bin/ss1-winexe-ungrab-input.sh" ] && "$WIN/bin/ss1-winexe-ungrab-input.sh" || true
[ -x "$WIN/bin/ss1-winexe-keep-input.sh" ] && "$WIN/bin/ss1-winexe-keep-input.sh" watch || true

LOGDIR="$WIN/logs"
mkdir -p "$LOGDIR"
WINELOG="$LOGDIR/wine-winexe-winamp.log"
: > "$WINELOG"

# Wine path for the optional MP3 (unix path → Z:).
WINMP3=""
case "$MP3" in
  *.mp3|*.MP3)
    if [ -f "$MP3" ]; then
      case "$MP3" in
        "$WIN/wineprefix-prebuilt/drive_c"/*)
          rel=${MP3#"$WIN/wineprefix-prebuilt/drive_c/"}
          WINMP3="C:\\$(echo "$rel" | sed 's|/|\\|g')"
          ;;
        *)
          WINMP3="Z:\\$(echo "$MP3" | sed 's|/|\\|g')"
          ;;
      esac
    fi
    ;;
esac

if [ -n "$WINMP3" ]; then
  setsid /bin/sh -c "exec $WIN/bin/wine explorer /desktop=ss1,640x480 'C:\\Program Files\\Winamp\\winamp.exe' '$WINMP3'" \
    </dev/null >>"$WINELOG" 2>&1 &
else
  setsid /bin/sh -c "exec $WIN/bin/wine explorer /desktop=ss1,640x480 'C:\\Program Files\\Winamp\\winamp.exe'" \
    </dev/null >>"$WINELOG" 2>&1 &
fi
echo $! > /tmp/ss1-wine.pid
echo "LAUNCHED core=$CORE wine=$(cat /tmp/ss1-wine.pid) mp3=${WINMP3:-none}"
echo "log=$WINELOG"
