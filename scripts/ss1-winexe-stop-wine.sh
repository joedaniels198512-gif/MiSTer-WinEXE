#!/bin/sh
# Stop the current WinEXE Wine application/session only.
# Keeps WinEXE_Test, dummy Xorg, SHM presenter, and the input-ungrab watcher.
# SIGTERM wineserver first (same request as wineserver -k, no extra Box86).
#
# Fast path: if no Wine processes exist, return immediately. Waits/timeouts
# and wineserver -k (Box86) run only when there is something to terminate.
#
#   ss1-winexe-stop-wine.sh          # stop + report
#   ss1-winexe-stop-wine.sh status   # report only
set +e
WIN="${WIN:-/media/fat/games/WinEXE}"
MODE=${1:-stop}

XORG_PID=$(cat /tmp/ss1-xorg.pid 2>/dev/null)
PRESENT_PID=$(cat /tmp/ss1-winexe-x11-present.pid 2>/dev/null)
KEEP_PID=$(cat /tmp/ss1-winexe-keep-input.pid 2>/dev/null)

STOP_T0=$(awk '{print $1}' /proc/uptime)
tlog() {
  now=$(awk '{print $1}' /proc/uptime)
  ms=$(awk -v a="$STOP_T0" -v b="$now" 'BEGIN { printf "%d", (b-a)*1000 }')
  echo "stop-wine +${ms}ms $*"
}

is_wine_comm() {
  case "$1" in
    wineserver|wine|wine-preloader|start.exe|explorer.exe| \
    winamp.exe|Winamp.exe|mspaint.exe|notepad.exe|NOTEPAD.EXE| \
    winmine.exe|sol.exe|freecell.exe|mshearts.exe| \
    civ2.exe|CIV2.EXE| \
    wmplayer.exe|WMPLAYER.EXE|wmplayer.ex|mspmspsv.exe| \
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

list_wine() {
  # stdout: "pid comm" lines. One /proc scan.
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    comm=$(cat "$d/comm" 2>/dev/null) || continue
    is_wine_comm "$comm" || continue
    echo "$pid $comm"
  done
}

report_wine() {
  echo "===== $1 ====="
  found=0
  while read -r pid comm; do
    [ -n "$pid" ] || continue
    rss=$(awk '/^VmRSS:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null)
    echo "pid=$pid rss_kB=${rss:-?} comm=$comm"
    found=1
  done <<EOF
$(list_wine)
EOF
  [ "$found" = 1 ] || echo "(none)"
}

wine_pid_alive() {
  if [ -f /tmp/ss1-wine.pid ]; then
    WP=$(cat /tmp/ss1-wine.pid)
    if [ -n "$WP" ] && [ -r "/proc/$WP/comm" ]; then
      return 0
    fi
  fi
  return 1
}

if [ "$MODE" = status ]; then
  report_wine "wine session"
  report_keep
  exit 0
fi

tlog "begin"

WINE_LIST=$(list_wine)
tlog "proc scan done"

if [ -z "$WINE_LIST" ] && ! wine_pid_alive; then
  if [ -f /tmp/ss1-winexe-sc2k-toolbar.pid ]; then
    "$WIN/bin/ss1-winexe-sc2k-toolbar.sh" stop >/dev/null 2>&1 || true
    tlog "sc2k-toolbar pidfile stop done"
  fi
  rm -f /tmp/ss1-wine.pid /tmp/ss1-wine.exe
  tlog "fast-path: no wine processes — skip TERM/sleep/wineserver -k"
  echo "===== wine session (before) ====="
  echo "(none)"
  echo "===== wine session (after) ====="
  echo "(none)"
  echo "STALE_WINE=0"
  report_keep
  tlog "exit fast-path"
  exit 0
fi

if [ -x "$WIN/bin/ss1-winexe-sc2k-toolbar.sh" ]; then
  "$WIN/bin/ss1-winexe-sc2k-toolbar.sh" stop >/dev/null 2>&1 || true
fi
tlog "sc2k-toolbar stop done"

report_wine "wine session (before)"
tlog "report before done"

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
tlog "wineserver/start TERM sent=$sent"

if [ "$sent" = 1 ]; then
  sleep 2
  tlog "slept 2 after wineserver TERM"
fi

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
tlog "leftover TERM sent=$sent"

if [ "$sent" = 1 ]; then
  sleep 2
  tlog "slept 2 after leftover TERM"
fi

avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
still=0
still_names=""
for d in /proc/[0-9]*; do
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  if is_wine_comm "$comm"; then
    still=1
    still_names="$still_names $comm"
  fi
done
tlog "post-TERM scan still=$still names='$still_names' MemAvailable=${avail}kB"

if [ "$still" = 1 ] && [ "${avail:-0}" -gt 32000 ]; then
  echo "wineserver -k MemAvailable=${avail}kB"
  export WINEARCH="${WINEARCH:-win32}"
  WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}" "$WIN/bin/wineserver" -k || true
  tlog "wineserver -k prefix-prebuilt done"
  [ -d "$WIN/wineprefix" ] && WINEPREFIX="$WIN/wineprefix" "$WIN/bin/wineserver" -k || true
  tlog "wineserver -k optional prefix done"
  sleep 2
  tlog "slept 2 after wineserver -k"
fi

for d in /proc/[0-9]*; do
  pid=${d#/proc/}
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  is_wine_comm "$comm" || continue
  echo "KILL leftover pid=$pid comm=$comm"
  kill -KILL "$pid" 2>/dev/null || true
done
tlog "KILL leftovers done"

rm -f /tmp/ss1-wine.pid /tmp/ss1-wine.exe

report_wine "wine session (after)"
stale=0
[ -n "$(list_wine)" ] && stale=1
if [ "$stale" = 1 ]; then
  echo "STALE_WINE=1" >&2
  [ -x "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" ] && \
    "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" restore >/dev/null 2>&1 || true
  report_keep
  tlog "exit STALE_WINE=1"
  exit 1
fi
echo "STALE_WINE=0"
if [ -f /tmp/ss1-wmp-dsound-clsid.override ] && [ -x "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" ]; then
  tlog "WMP CLSID restore (stamp present)"
  "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" restore >/dev/null 2>&1 || true
  tlog "WMP CLSID restore done"
fi
report_keep
tlog "exit STALE_WINE=0"
