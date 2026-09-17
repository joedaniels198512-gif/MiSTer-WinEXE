#!/bin/sh
# Launch genuine XP SP3 WMP9 (wmplayer.exe 9.00.00.4503) on the EXISTING
# WinEXE stack. 60 Hz general-app profile. WMP session uses box86-gstflow;
# original /media/fat/Windows/bin/wine (Box86) is not replaced.
set -e
WIN=/media/fat/Windows
EXE="$WIN/wineprefix-prebuilt/drive_c/Program Files/Windows Media Player/wmplayer.exe"
WINE="$WIN/bin/wine-gstflow"
MEDIA=${1:-}

win_media_path() {
  f=$1
  case "$f" in
    [Cc]:\\*|[Cc]:/*) echo "$f"; return ;;
    "$WIN/wineprefix-prebuilt/drive_c"/*)
      rel=${f#"$WIN/wineprefix-prebuilt/drive_c/"}
      echo "C:\\$(echo "$rel" | sed 's|/|\\|g')"
      ;;
    /*)
      echo "Z:\\$(echo "$f" | sed 's|/|\\|g')"
      ;;
    *)
      echo "$f"
      ;;
  esac
}

if [ -z "$MEDIA" ]; then
  if [ -f "$WIN/wineprefix-prebuilt/drive_c/tone.wav" ]; then
    MEDIA="$WIN/wineprefix-prebuilt/drive_c/tone.wav"
  fi
fi
WINMEDIA=""
[ -n "$MEDIA" ] && WINMEDIA=$(win_media_path "$MEDIA")

if [ ! -x "$WINE" ]; then
  echo "missing $WINE (WMP box86-gstflow wrapper)" >&2
  exit 1
fi
[ -f "$EXE" ] || { echo "missing $EXE — run ss1-winexe-wmp9-install.sh" >&2; exit 1; }

"$WIN/bin/ss1-mount-prefix.sh"
export WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
"$WIN/bin/ss1-winexe-stop-wine.sh"

CORE=$(cat /tmp/CORENAME 2>/dev/null || true)
if [ "$CORE" != "WinEXE_Test" ]; then
  echo "loading WinEXE_Test.rbf (was '$CORE')"
  echo "load_core /media/fat/WinEXE_Test.rbf" > /dev/MiSTer_cmd
  i=0
  while [ "$i" -lt 20 ]; do
    CORE=$(cat /tmp/CORENAME 2>/dev/null || true)
    [ "$CORE" = "WinEXE_Test" ] && break
    i=$((i + 1))
    sleep 1
  done
fi
[ "$CORE" = "WinEXE_Test" ] || { echo "core is '$CORE', need WinEXE_Test" >&2; exit 1; }

"$WIN/bin/ss1-winexe-xorg.sh" start
[ -S /tmp/.X11-unix/X0 ] || { echo "dummy Xorg :0 not running" >&2; exit 1; }

if [ -x "$WIN/bin/ss1-winexe-present-restart.sh" ]; then
  SS1_HZ=60 SS1_SKIP_UNCHANGED=1 SS1_DIRTY=0 "$WIN/bin/ss1-winexe-present-restart.sh"
fi
[ -f /tmp/ss1-winexe-x11-present.pid ] && kill -0 "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null \
  || { echo "ss1-winexe-x11-present not running" >&2; exit 1; }

for d in /proc/[0-9]*; do
  c=$(cat "$d/comm" 2>/dev/null) || continue
  case "$c" in
    Xorg|ss1-winexe-x11-*) taskset -p 0x3 "${d#/proc/}" >/dev/null 2>&1 || true ;;
  esac
done

[ -x "$WIN/bin/ss1-winexe-wmp9-config.sh" ] && "$WIN/bin/ss1-winexe-wmp9-config.sh" || true

export DISPLAY=:0
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mshtml=d;ieframe=d;shdocvw=d"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err}"
export BOX86_LOG="${BOX86_LOG:-0}"
export BOX86_NOBANNER=1
export WINELOADER="$WINE"
export SS1WO_LOG="${SS1WO_LOG:-1}"
# Plan B (default): WMP-session CLSID override so quartz CoCreate of
# DSound/AudioRender instantiates ss1waveout.ax. No extra Wine PE.
# Plan A helper (inject/ROT) is optional — it cost ~40 MB and helped OOM WMP.
if [ "${SS1_WMP_WAVEOUT_CLSID:-1}" != "0" ]; then
  export SS1WO_ALIAS_DSOUND=1
  [ -x "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" ] && \
    "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" apply || true
else
  unset SS1WO_ALIAS_DSOUND
fi
. "$WIN/bin/ss1-x11-env.sh"
[ -x "$WIN/bin/ss1-winexe-gst-env.sh" ] && . "$WIN/bin/ss1-winexe-gst-env.sh"
export GST_DEBUG="${GST_DEBUG:-1}"

PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
if [ "${SS1_WMP_WAVEOUT:-1}" != "0" ]; then
  SYS32="$PREFIX/drive_c/windows/system32"
  mkdir -p "$SYS32" "$PREFIX/drive_c/windows/temp"
  if [ -f "$WIN/bin/ss1waveout.ax" ]; then
    cp -f "$WIN/bin/ss1waveout.ax" "$SYS32/ss1waveout.ax"
    cp -f "$WIN/bin/ss1waveout.ax" "$PREFIX/drive_c/ss1waveout.ax"
    echo "staged $SYS32/ss1waveout.ax"
  else
    echo "WARN missing $WIN/bin/ss1waveout.ax" >&2
  fi
  # Method B: do not stage injector/helper PE unless explicitly requested.
  if [ "${SS1_WMP_WAVEOUT_HELPER:-0}" != "0" ]; then
    if [ -f "$WIN/bin/ss1wmpinj.dll" ]; then
      cp -f "$WIN/bin/ss1wmpinj.dll" "$SYS32/ss1wmpinj.dll"
      cp -f "$WIN/bin/ss1wmpinj.dll" "$PREFIX/drive_c/ss1wmpinj.dll"
    fi
    if [ -f "$WIN/bin/ss1-winexe-wmpwo.exe" ]; then
      cp -f "$WIN/bin/ss1-winexe-wmpwo.exe" "$PREFIX/drive_c/ss1-winexe-wmpwo.exe"
    fi
  fi
fi

[ -x "$WIN/bin/ss1-winexe-ungrab-input.sh" ] && "$WIN/bin/ss1-winexe-ungrab-input.sh" || true
[ -x "$WIN/bin/ss1-winexe-keep-input.sh" ] && "$WIN/bin/ss1-winexe-keep-input.sh" watch || true

LOGDIR="$WIN/logs"
mkdir -p "$LOGDIR"
WINELOG="$LOGDIR/wine-winexe-wmp9.log"
: > "$WINELOG"

if [ -n "$WINMEDIA" ]; then
  setsid /bin/sh -c "exec $WINE explorer /desktop=ss1,640x480 'C:\\Program Files\\Windows Media Player\\wmplayer.exe' /Play '$WINMEDIA'" \
    </dev/null >>"$WINELOG" 2>&1 &
else
  setsid /bin/sh -c "exec $WINE explorer /desktop=ss1,640x480 'C:\\Program Files\\Windows Media Player\\wmplayer.exe'" \
    </dev/null >>"$WINELOG" 2>&1 &
fi
echo $! > /tmp/ss1-wine.pid
echo "LAUNCHED core=$CORE wine=$(cat /tmp/ss1-wine.pid) box86=gstflow exe=wmplayer.exe media=${WINMEDIA:-none}"
echo "log=$WINELOG"

if [ "${SS1_WMP_WAVEOUT_HELPER:-0}" != "0" ] && [ -f "$PREFIX/drive_c/ss1-winexe-wmpwo.exe" ]; then
  WMPWOLOG="$LOGDIR/ss1-winexe-wmpwo.log"
  : > "$WMPWOLOG"
  setsid /bin/sh -c "exec $WINE 'C:\\ss1-winexe-wmpwo.exe'" \
    </dev/null >>"$WMPWOLOG" 2>&1 &
  echo $! > /tmp/ss1-wmpwo.pid
  echo "WMPWO helper pid=$(cat /tmp/ss1-wmpwo.pid) log=$WMPWOLOG method=A"
else
  echo "WMPWO method=B CLSID override (no extra helper PE) alias=${SS1WO_ALIAS_DSOUND:-off}"
fi
