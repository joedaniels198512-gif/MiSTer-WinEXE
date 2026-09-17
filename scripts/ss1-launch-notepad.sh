#!/bin/sh
# Persistently launch Xorg + presenter + Wine notepad on SuperStation One.
# Uses setsid so SSH logout does not SIGHUP the stack.
# Logs and PIDs live under /media/fat/Windows/logs/.
set -e
WIN=/media/fat/Windows
LOGDIR="$WIN/logs"
mkdir -p "$LOGDIR" /tmp/bin /tmp/xorg.conf.d
STAMP=$(date +%Y%m%d_%H%M%S)
WATCH="$LOGDIR/watchdog.log"

log() { echo "$(date '+%F %T') $*" | tee -a "$WATCH"; }

# Stop previous instance of OUR stack only.
if [ -f /tmp/ss1-watchdog.pid ]; then
  kill "$(cat /tmp/ss1-watchdog.pid)" 2>/dev/null || true
fi
if [ -f /tmp/ss1-present.pid ]; then
  PP=$(cat /tmp/ss1-present.pid)
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    ppid=$(awk '{print $4}' "$d/stat" 2>/dev/null) || continue
    [ "$ppid" = "$PP" ] && kill "$pid" 2>/dev/null || true
  done
  kill "$PP" 2>/dev/null || true
fi
if [ -f /tmp/ss1-wine.pid ]; then
  kill "$(cat /tmp/ss1-wine.pid)" 2>/dev/null || true
fi
WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
export WINEPREFIX
"$WIN/bin/wineserver" -k 2>/dev/null || true
"$WIN/bin/ss1-xorg.sh" stop >/dev/null 2>&1 || true
sleep 1

"$WIN/bin/ss1-mount-prefix.sh"

"$WIN/bin/ss1-xorg.sh" start
XPID=$(cat /tmp/ss1-xorg.pid)
export DISPLAY=:0
export LD_LIBRARY_PATH="$WIN/x11/lib:$WIN/host-libs/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$WIN/x11/bin/xset" s off -dpms >/dev/null 2>&1 || true
"$WIN/x11/bin/xsetroot" -solid '#001040' || true

# Presenter: copy /dev/fb0 -> Menu HPS n=1 forever.
export SS1_PRESENT_LOG="$LOGDIR/ss1-present.log"
: > "$SS1_PRESENT_LOG"
setsid /bin/sh -c "exec $WIN/bin/ss1-fb-present.sh loop 0" </dev/null >>"$SS1_PRESENT_LOG" 2>&1 &
echo $! > /tmp/ss1-present.pid
PPID_PRESENT=$!

export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err}"
WINELOG="$LOGDIR/wine-notepad.log"
: > "$WINELOG"
# Sized Wine desktop so explorer cannot cover the X root with a black 1920x1080 window.
setsid /bin/sh -c "exec $WIN/bin/wine explorer /desktop=ss1,1024x768 notepad" </dev/null >>"$WINELOG" 2>&1 &
echo $! > /tmp/ss1-wine.pid
WPID=$!

log "launch stamp=$STAMP xorg=$XPID present=$PPID_PRESENT wine=$WPID"
log "xorg_cmd=$(tr '\0' ' ' < /proc/$XPID/cmdline 2>/dev/null)"
echo "$XPID" > "$LOGDIR/pids.xorg"
echo "$PPID_PRESENT" > "$LOGDIR/pids.present"
echo "$WPID" > "$LOGDIR/pids.wine"

# Watchdog: log which of the three PIDs dies first. Never attached to SSH.
setsid /bin/sh -c "
while :; do
  ts=\$(date '+%F %T')
  mem=\$(awk '/MemAvailable/ {print \$2}' /proc/meminfo)
  xs=dead; ps=dead; ws=dead
  kill -0 $XPID 2>/dev/null && xs=alive
  kill -0 $PPID_PRESENT 2>/dev/null && ps=alive
  # wine parent or notepad
  if kill -0 $WPID 2>/dev/null || ps | grep -q '[n]otepad'; then
    ws=alive
  fi
  np=\$(ps | awk '/[n]otepad/ {printf \"%s,\", \$1}')
  echo \"\$ts mem=\${mem}kB xorg=\$xs present=\$ps wine=\$ws notepad_pids=\$np\" >> $WATCH
  if [ \$xs = dead ]; then
    echo \"\$ts FIRST_DEAD=xorg\" >> $WATCH
    tail -80 $LOGDIR/Xorg.0.log >> $WATCH
    break
  fi
  if [ \$ps = dead ]; then
    echo \"\$ts FIRST_DEAD=present\" >> $WATCH
    tail -40 $LOGDIR/ss1-present.log >> $WATCH
    break
  fi
  if [ \$ws = dead ]; then
    echo \"\$ts FIRST_DEAD=wine\" >> $WATCH
    tail -80 $WINELOG >> $WATCH
    break
  fi
  sleep 5
done
" </dev/null >>"$WATCH" 2>&1 &
echo $! > /tmp/ss1-watchdog.pid
log "watchdog_pid=$(cat /tmp/ss1-watchdog.pid)"
echo "LAUNCHED xorg=$XPID present=$PPID_PRESENT wine=$WPID watchdog=$(cat /tmp/ss1-watchdog.pid)"
echo "logs: $WATCH $WINELOG $SS1_PRESENT_LOG $LOGDIR/Xorg.0.log"
