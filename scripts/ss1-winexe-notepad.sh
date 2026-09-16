#!/bin/sh
# WinEXE_Test GUI path: dummy Xorg 640x480 → ARM presenter → 0x30000000.
# Does not use /dev/fb0, ss1-fb-present, or F9. Does not change Box86/Wine.
set -e
WIN=/media/fat/Windows
LOGDIR="$WIN/logs"
mkdir -p "$LOGDIR" /tmp/bin /tmp/xorg.conf.d

stop_old_presentation() {
  # Leave the scripts on disk; just stop the parked fb0/n=1 path.
  if [ -f /tmp/ss1-watchdog.pid ]; then
    kill "$(cat /tmp/ss1-watchdog.pid)" 2>/dev/null || true
    rm -f /tmp/ss1-watchdog.pid
  fi
  if [ -f /tmp/ss1-present.pid ]; then
    PP=$(cat /tmp/ss1-present.pid)
    for d in /proc/[0-9]*; do
      pid=${d#/proc/}
      ppid=$(awk '{print $4}' "$d/stat" 2>/dev/null) || continue
      [ "$ppid" = "$PP" ] && kill "$pid" 2>/dev/null || true
    done
    kill "$PP" 2>/dev/null || true
    rm -f /tmp/ss1-present.pid
  fi
  for pid in $(ps | awk '/ss1-fb-present/{print $1}'); do
    kill "$pid" 2>/dev/null || true
  done
  if [ -f /tmp/ss1-winexe-x11-present.pid ]; then
    kill "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null || true
    rm -f /tmp/ss1-winexe-x11-present.pid
  fi
  for pid in $(ps | awk '/ss1-winexe-x11-present/{print $1}'); do
    kill "$pid" 2>/dev/null || true
  done
  if [ -f /tmp/ss1-wine.pid ]; then
    kill "$(cat /tmp/ss1-wine.pid)" 2>/dev/null || true
    rm -f /tmp/ss1-wine.pid
  fi
  WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
  export WINEPREFIX
  "$WIN/bin/wineserver" -k 2>/dev/null || true
  "$WIN/bin/ss1-xorg.sh" stop >/dev/null 2>&1 || true
  sleep 1
}

if [ ! -x "$WIN/bin/ss1-winexe-x11-present" ]; then
  echo "missing $WIN/bin/ss1-winexe-x11-present (GHA ARM artifact)" >&2
  exit 1
fi
if [ ! -f "$WIN/x11/lib/xorg/modules/drivers/dummy_drv.so" ]; then
  echo "missing dummy_drv.so" >&2
  exit 1
fi
if [ ! -f "$WIN/apps/notepad.exe" ]; then
  echo "missing $WIN/apps/notepad.exe" >&2
  exit 1
fi

stop_old_presentation

CORE=$(cat /tmp/CORENAME 2>/dev/null || true)
if [ "$CORE" != "WinEXE_Test" ]; then
  echo "loading WinEXE_Test.rbf (was '$CORE')"
  echo "load_core /media/fat/WinEXE_Test.rbf" > /dev/MiSTer_cmd
  sleep 6
  CORE=$(cat /tmp/CORENAME 2>/dev/null || true)
fi
echo "core=$CORE"

"$WIN/bin/ss1-mount-prefix.sh"
mkdir -p "$WIN/x11/etc/X11"
cp "$WIN/bin/xorg.winexe.conf" "$WIN/x11/etc/X11/xorg.winexe.conf"

"$WIN/bin/ss1-winexe-xorg.sh" start
export DISPLAY=:0
export LD_LIBRARY_PATH="$WIN/x11/lib:$WIN/host-libs/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$WIN/x11/bin/xset" s off -dpms >/dev/null 2>&1 || true
"$WIN/x11/bin/xsetroot" -solid navy >/dev/null 2>&1 || true

PRESLOG="$LOGDIR/ss1-winexe-x11-present.log"
: > "$PRESLOG"
setsid "$WIN/bin/ss1-winexe-x11-present" </dev/null >>"$PRESLOG" 2>&1 &
echo $! > /tmp/ss1-winexe-x11-present.pid
sleep 1
if ! kill -0 "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null; then
  echo "presenter exited; see $PRESLOG" >&2
  tail -20 "$PRESLOG" >&2 || true
  exit 1
fi

export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err}"
. "$WIN/bin/ss1-x11-env.sh"
WINELOG="$LOGDIR/wine-winexe-notepad.log"
: > "$WINELOG"
setsid /bin/sh -c "exec $WIN/bin/wine explorer /desktop=ss1,640x480 $WIN/apps/notepad.exe" \
  </dev/null >>"$WINELOG" 2>&1 &
echo $! > /tmp/ss1-wine.pid

echo "LAUNCHED core=$CORE xorg=$(cat /tmp/ss1-xorg.pid) present=$(cat /tmp/ss1-winexe-x11-present.pid) wine=$(cat /tmp/ss1-wine.pid)"
echo "logs: $PRESLOG $WINELOG $WIN/logs/Xorg.winexe.log"
echo "HDMI is FPGA ascal of 0x30000000 — not /dev/fb0"
