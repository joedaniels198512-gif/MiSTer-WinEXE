#!/bin/sh
# WMP9 PCM listen: full WinEXE stack + SS1 WaveOut intercept (method A).
# Leaves WMP running for physical listen. Aborts if MemAvailable < 50 MB.
# Usage: ss1-winexe-wmp9-pcm.sh [windows-or-unix media path]
set +e
WIN="${WIN:-/media/fat/Windows}"
MEDIA="${1:-C:\\tone.wav}"
LOG="${LOG:-$WIN/logs/ss1-winexe-wmp9-pcm.log}"
ABORT_KB="${SS1_MEM_ABORT_KB:-51200}"

mem() {
  awk '/^MemAvailable:/{a=$2} /^MemFree:/{f=$2} /^AnonPages:/{n=$2} END{printf "MemAvailable=%s MemFree=%s AnonPages=%s\n", a, f, n}' /proc/meminfo
}
avail_kb() {
  awk '/^MemAvailable:/{print $2}' /proc/meminfo
}

mkdir -p "$WIN/logs"
: > "$LOG"
{
  echo "===== WMP9 PCM WaveOut $(date -u +%Y-%m-%dT%H:%M:%SZ) media=$MEDIA ====="
  echo "===== mem before WMP ====="
  mem
} | tee -a "$LOG"
[ -x "$WIN/bin/ss1-winexe-mem-wine.sh" ] && "$WIN/bin/ss1-winexe-mem-wine.sh" | tee -a "$LOG"

"$WIN/bin/ss1-winexe-wmp9.sh" "$MEDIA" 2>&1 | tee -a "$LOG"

echo "===== mem after launch =====" | tee -a "$LOG"
mem | tee -a "$LOG"
[ -x "$WIN/bin/ss1-winexe-mem-wine.sh" ] && "$WIN/bin/ss1-winexe-mem-wine.sh" | tee -a "$LOG"

i=0
while [ "$i" -lt 48 ]; do
  a=$(avail_kb)
  if [ $((i % 4)) -eq 0 ]; then
    echo "===== t+${i}s MemAvailable=${a}kB =====" | tee -a "$LOG"
  fi
  if [ -n "$a" ] && [ "$a" -lt "$ABORT_KB" ]; then
    echo "ABORT MemAvailable=${a}kB < ${ABORT_KB}kB — stopping Wine" | tee -a "$LOG"
    "$WIN/bin/ss1-winexe-stop-wine.sh" | tee -a "$LOG"
    echo "===== mem after abort stop =====" | tee -a "$LOG"
    mem | tee -a "$LOG"
    exit 2
  fi
  if [ "$i" -eq 8 ] || [ "$i" -eq 16 ] || [ "$i" -eq 24 ]; then
    if [ -n "$a" ] && [ "$a" -gt 100000 ]; then
      [ -x "$WIN/bin/ss1-winexe-mem-wine.sh" ] && "$WIN/bin/ss1-winexe-mem-wine.sh" | tee -a "$LOG"
    fi
    echo "===== alsa t+${i}s =====" | tee -a "$LOG"
    cat /proc/asound/card0/pcm0p/sub0/status 2>/dev/null | head -8 | tee -a "$LOG"
    echo "===== WMPWO =====" | tee -a "$LOG"
    grep -E "WMPWO: (FILTER |SCAN |SWAP |graph has no|inject|wmplayer|ss1_ok|ROT |FAIL )" \
      "$WIN/logs/ss1-winexe-wmpwo.log" "$WIN/logs/wine-winexe-wmp9.log" 2>/dev/null | tail -80 | tee -a "$LOG"
    echo "===== SS1WO =====" | tee -a "$LOG"
    grep -E "SS1WO: (created|waveOutOpen|paused|first |playback released|STARVE|WRITE_ABORT|PCM tally|GAP |STAT |EndOfStream|EOS drained|EC_COMPLETE|alias )" \
      "$WIN/logs/wine-winexe-wmp9.log" 2>/dev/null | tail -40 | tee -a "$LOG"
  fi
  i=$((i + 1))
  sleep 1
done

echo "===== mem during/after first ~24s =====" | tee -a "$LOG"
mem | tee -a "$LOG"
[ -x "$WIN/bin/ss1-winexe-mem-wine.sh" ] && "$WIN/bin/ss1-winexe-mem-wine.sh" | tee -a "$LOG"
echo "LEAVE_RUNNING WMP+WaveOut for physical listen. log=$LOG"
echo "stop later: $WIN/bin/ss1-winexe-stop-wine.sh"
exit 0
