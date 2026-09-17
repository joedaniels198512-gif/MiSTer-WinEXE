#!/bin/sh
# Stop the current WinEXE Wine application/session only.
# Keeps WinEXE_Test, dummy Xorg, SHM presenter, and the input-ungrab watcher.
# SIGTERM wineserver first (same request as wineserver -k, no extra Box86).
#
#   ss1-winexe-stop-wine.sh          # stop + report
#   ss1-winexe-stop-wine.sh status   # report only
set +e
WIN="${WIN:-/media/fat/Windows}"
MODE=${1:-stop}

XORG_PID=$(cat /tmp/ss1-xorg.pid 2>/dev/null)
PRESENT_PID=$(cat /tmp/ss1-winexe-x11-present.pid 2>/dev/null)
KEEP_PID=$(cat /tmp/ss1-winexe-keep-input.pid 2>/dev/null)

is_wine_comm() {
  case "$1" in
    wineserver|wine|wine-preloader|start.exe|explorer.exe| \
    winamp.exe|Winamp.exe|mspaint.exe|notepad.exe|NOTEPAD.EXE| \
    wmplayer.exe|WMPLAYER.EXE|wmplayer.ex| \
    ss1-winexe-wmpw|ss1-winexe-dsho|ss1-winexe-cocr| \
    SIMCITY.EXE|simcity.exe|SIMCITY.exe| \
    services.exe|rpcss.exe|winedevice.exe|plugplay.exe| \
    wineboot.exe|control.exe|svchost.exe|conhost.exe| \
    winemenubuilder.exe|msiexec.exe)
      return 0 ;;
  esac
  return 1
}

report_keep() {
  echo "===== keep-alive ====="
  echo "core=$(cat /tmp/CORENAME 2>/dev/null || echo '?')"
  for spec in "Xorg:$XORG_PID" "presenter:$PRESENT_PID" "keep-input:$KEEP_PID"; do
    label=${spec%%:*}
    pid=${spec#*:}
    if [ -n "$pid" ] && [ -r "/proc/$pid/comm" ]; then
      rss=$(awk '/^VmRSS:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null)
      echo "$label pid=$pid rss_kB=${rss:-?} comm=$(cat /proc/$pid/comm)"
    else
      echo "$label missing (expected to stay up)"
    fi
  done
  echo "===== mem ====="
  grep -E '^(MemTotal|MemFree|MemAvailable):' /proc/meminfo
}

report_wine() {
  echo "===== $1 ====="
  found=0
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    comm=$(cat "$d/comm" 2>/dev/null) || continue
    is_wine_comm "$comm" || continue
    rss=$(awk '/^VmRSS:/{print $2; exit}' "$d/status" 2>/dev/null)
    echo "pid=$pid rss_kB=${rss:-?} comm=$comm"
    found=1
  done
  [ "$found" = 1 ] || echo "(none)"
}

if [ "$MODE" = status ]; then
  report_wine "wine session"
  report_keep
  exit 0
fi

if [ -x "$WIN/bin/ss1-winexe-sc2k-toolbar.sh" ]; then
  "$WIN/bin/ss1-winexe-sc2k-toolbar.sh" stop >/dev/null 2>&1 || true
fi

report_wine "wine session (before)"

# SIGTERM wineserver first so clients exit with the session.
sent=0
for d in /proc/[0-9]*; do
  pid=${d#/proc/}
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  [ "$comm" = wineserver ] || continue
  echo "TERM wineserver pid=$pid"
  kill -TERM "$pid" 2>/dev/null || true
  sent=1
done

if [ -f /tmp/ss1-wine.pid ]; then
  WP=$(cat /tmp/ss1-wine.pid)
  if [ -n "$WP" ] && [ -r "/proc/$WP/comm" ]; then
    echo "TERM ss1-wine.pid=$WP comm=$(cat /proc/$WP/comm)"
    kill -TERM "$WP" 2>/dev/null || true
    sent=1
  fi
fi

[ "$sent" = 1 ] && sleep 2

# Remaining Wine apps / helpers.
sent=0
for d in /proc/[0-9]*; do
  pid=${d#/proc/}
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  is_wine_comm "$comm" || continue
  echo "TERM leftover pid=$pid comm=$comm"
  kill -TERM "$pid" 2>/dev/null || true
  sent=1
done

[ "$sent" = 1 ] && sleep 2

avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
still=0
for d in /proc/[0-9]*; do
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  is_wine_comm "$comm" && still=1 && break
done
if [ "$still" = 1 ] && [ "${avail:-0}" -gt 32000 ]; then
  echo "wineserver -k MemAvailable=${avail}kB"
  export WINEARCH="${WINEARCH:-win32}"
  WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}" "$WIN/bin/wineserver" -k || true
  [ -d "$WIN/wineprefix" ] && WINEPREFIX="$WIN/wineprefix" "$WIN/bin/wineserver" -k || true
  sleep 2
fi

for d in /proc/[0-9]*; do
  pid=${d#/proc/}
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  is_wine_comm "$comm" || continue
  echo "KILL leftover pid=$pid comm=$comm"
  kill -KILL "$pid" 2>/dev/null || true
done

rm -f /tmp/ss1-wine.pid /tmp/ss1-wine.exe

report_wine "wine session (after)"
stale=0
for d in /proc/[0-9]*; do
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  is_wine_comm "$comm" && stale=1 && break
done
if [ "$stale" = 1 ]; then
  echo "STALE_WINE=1" >&2
  [ -x "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" ] && \
    "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" restore >/dev/null 2>&1 || true
  report_keep
  exit 1
fi
echo "STALE_WINE=0"
if [ -x "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" ]; then
  "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" restore >/dev/null 2>&1 || true
fi
report_keep
