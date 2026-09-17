#!/bin/sh
# WMP9 PCM listen: Method B CLSID override only (no injector/helper PE).
# Aborts and restores quartz if MemAvailable < 120 MB.
# Usage: ss1-winexe-wmp9-pcm.sh [windows-or-unix media path]
set +e
WIN="${WIN:-/media/fat/Windows}"
MEDIA="${1:-C:\\tone30.wav}"
LOG="${LOG:-$WIN/logs/ss1-winexe-wmp9-pcm.log}"
ABORT_KB="${SS1_MEM_ABORT_KB:-122880}"
export SS1_WMP_WAVEOUT_HELPER=0
export SS1_WMP_WAVEOUT_CLSID=1
export SS1WO_LOG="${SS1WO_LOG:-1}"

mem() {
  awk '/^MemAvailable:/{a=$2} /^MemFree:/{f=$2} /^AnonPages:/{n=$2} END{printf "MemAvailable=%s MemFree=%s AnonPages=%s\n", a, f, n}' /proc/meminfo
}
avail_kb() {
  awk '/^MemAvailable:/{print $2}' /proc/meminfo
}

# Cheap 1 Hz line: MemAvailable/AnonPages + RSS of Wine/WMP comms. No smaps.
rss_line() {
  awk '/^MemAvailable:/{a=$2} /^AnonPages:/{n=$2} END{printf "avail=%s anon=%s", a, n}' /proc/meminfo
  for d in /proc/[0-9]*; do
    comm=$(cat "$d/comm" 2>/dev/null) || continue
    case "$comm" in
      wmplayer.exe|wmplayer.ex|explorer.exe|start.exe|wineserver| \
      services.exe|winedevice.exe|plugplay.exe|rpcss.exe|svchost.exe| \
      wine-preloader|wine|ss1-winexe-wmpw)
        rss=$(awk '/^VmRSS:/{print $2; exit}' "$d/status" 2>/dev/null)
        printf " %s:%s" "$comm" "${rss:--}"
        ;;
    esac
  done
  printf "\n"
}

do_abort() {
  echo "ABORT MemAvailable=$(avail_kb)kB < ${ABORT_KB}kB — stopping Wine" | tee -a "$LOG"
  rss_line | tee -a "$LOG"
  "$WIN/bin/ss1-winexe-stop-wine.sh" | tee -a "$LOG"
  echo "===== mem after abort stop =====" | tee -a "$LOG"
  mem | tee -a "$LOG"
  [ -x "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" ] && \
    "$WIN/bin/ss1-winexe-wmp9-waveout-clsid.sh" restore | tee -a "$LOG"
}

mkdir -p "$WIN/logs"
: > "$LOG"
{
  echo "===== WMP9 PCM Method B $(date -u +%Y-%m-%dT%H:%M:%SZ) media=$MEDIA abort_kb=$ABORT_KB ====="
  echo "===== mem before WMP ====="
  mem
} | tee -a "$LOG"

WATCHDOG_FLAG=/tmp/ss1-wmp9-watchdog.run
ABORT_FLAG=/tmp/ss1-wmp9-watchdog.abort
rm -f "$ABORT_FLAG"
echo 1 > "$WATCHDOG_FLAG"
(
  t=0
  while [ -f "$WATCHDOG_FLAG" ]; do
    a=$(avail_kb)
    echo "t+${t}s $(rss_line)" >>"$LOG"
    if [ -n "$a" ] && [ "$a" -lt "$ABORT_KB" ]; then
      echo 1 > "$ABORT_FLAG"
      rm -f "$WATCHDOG_FLAG"
      do_abort
      exit 2
    fi
    t=$((t + 1))
    sleep 1
  done
) &
WATCH_PID=$!

"$WIN/bin/ss1-winexe-wmp9.sh" "$MEDIA" 2>&1 | tee -a "$LOG"
LAUNCH_RC=$?

if [ -f "$ABORT_FLAG" ]; then
  wait "$WATCH_PID" 2>/dev/null
  echo "STOPPED by 120 MB watchdog during/after launch. log=$LOG"
  exit 2
fi

echo "===== mem after launch =====" | tee -a "$LOG"
mem | tee -a "$LOG"
a=$(avail_kb)
if [ -n "$a" ] && [ "$a" -gt 150000 ] && [ -x "$WIN/bin/ss1-winexe-mem-wine.sh" ]; then
  "$WIN/bin/ss1-winexe-mem-wine.sh" | tee -a "$LOG"
fi

# ~25 s listen window with watchdog still running.
i=0
while [ "$i" -lt 25 ]; do
  [ -f "$ABORT_FLAG" ] && break
  if [ "$i" -eq 8 ] || [ "$i" -eq 16 ] || [ "$i" -eq 24 ]; then
    echo "===== alsa t+${i}s =====" | tee -a "$LOG"
    cat /proc/asound/card0/pcm0p/sub0/status 2>/dev/null | head -8 | tee -a "$LOG"
    echo "===== SS1WO =====" | tee -a "$LOG"
    grep -E "SS1WO: (created|DllGetClassObject alias|waveOutOpen|paused|first |playback released|STARVE|WRITE_ABORT|PCM tally|GAP |STAT |EndOfStream|EOS drained|EC_COMPLETE)" \
      "$WIN/logs/wine-winexe-wmp9.log" 2>/dev/null | tail -40 | tee -a "$LOG"
    echo "===== dsound? =====" | tee -a "$LOG"
    grep -Ei "dsound|DirectSound" "$WIN/logs/wine-winexe-wmp9.log" 2>/dev/null | grep -v winemenubuilder | tail -20 | tee -a "$LOG"
  fi
  i=$((i + 1))
  sleep 1
done

rm -f "$WATCHDOG_FLAG"
wait "$WATCH_PID" 2>/dev/null

if [ -f "$ABORT_FLAG" ]; then
  echo "STOPPED by 120 MB watchdog during listen. log=$LOG"
  exit 2
fi

echo "===== mem after listen window =====" | tee -a "$LOG"
mem | tee -a "$LOG"
echo "===== SS1WO final =====" | tee -a "$LOG"
grep -E "SS1WO: (created|DllGetClassObject alias|waveOutOpen|paused|first |playback released|STARVE|WRITE_ABORT|PCM tally|GAP |STAT |EndOfStream|EOS drained|EC_COMPLETE)" \
  "$WIN/logs/wine-winexe-wmp9.log" 2>/dev/null | tail -50 | tee -a "$LOG"

echo "LEAVE_RUNNING only if graph is SS1 WaveOut and RAM is stable. log=$LOG"
echo "stop later: $WIN/bin/ss1-winexe-stop-wine.sh"
exit 0
