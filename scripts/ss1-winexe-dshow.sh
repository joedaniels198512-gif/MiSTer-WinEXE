#!/bin/sh
# Stage 1: minimal Wine DirectShow PCM WAV graph via box86-gstflow.
# Does not launch WMP. Does not overwrite original Box86.
set +e
WIN="${WIN:-/media/fat/Windows}"
BOX86="${BOX86:-$WIN/box86-ss1/box86-gstflow}"
WINEELF="$WIN/wine-installer/opt/wine-devel/bin/wine"
EXE="${EXE:-$WIN/bin/ss1-winexe-dshow.exe}"
LOG="${LOG:-$WIN/logs/ss1-winexe-dshow-ss1waveout.log}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
AX="${AX:-$WIN/bin/ss1waveout.ax}"

mem() {
  awk '/^MemAvailable:/{a=$2} /^MemFree:/{f=$2} /^AnonPages:/{n=$2} END{printf "MemAvailable=%s MemFree=%s AnonPages=%s\n", a, f, n}' /proc/meminfo
}

alsa() {
  echo "===== alsa $1 ====="
  cat /proc/asound/cards 2>/dev/null
  for s in /proc/asound/card0/pcm0p/sub0/status /proc/asound/card0/pcm0p/sub0/hw_params; do
    [ -r "$s" ] || continue
    echo "-- $s --"
    cat "$s"
  done
}

echo "===== before ====="
mem
ls -l "$BOX86" "$WIN/box86-ss1/box86" "$EXE" "$AX" 2>/dev/null
"$BOX86" -v 2>&1 | head -2

[ -x "$BOX86" ] || { echo "missing $BOX86" >&2; exit 1; }
[ -x "$WINEELF" ] || { echo "missing $WINEELF" >&2; exit 1; }
[ -f "$EXE" ] || { echo "missing $EXE" >&2; exit 1; }
[ -f "$AX" ] || { echo "missing $AX" >&2; exit 1; }
[ -x "$WIN/box86-ss1/box86" ] || { echo "original box86 missing" >&2; exit 1; }

"$WIN/bin/ss1-mount-prefix.sh" || exit 1
export WINEPREFIX="$PREFIX"
export WINEARCH=win32

# Dummy Xorg for Wine window station only. No presenter (audio-only).
if [ -x "$WIN/bin/ss1-winexe-xorg.sh" ]; then
  "$WIN/bin/ss1-winexe-xorg.sh" start || true
fi

"$WIN/bin/ss1-winexe-stop-wine.sh"

# Stop presenter if leftover from WMP — keep the machine idle for this listen test.
if [ -f /tmp/ss1-winexe-x11-present.pid ]; then
  kill "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null || true
  rm -f /tmp/ss1-winexe-x11-present.pid
fi
for d in /proc/[0-9]*; do
  c=$(cat "$d/comm" 2>/dev/null) || continue
  case "$c" in
    ss1-winexe-x11-*) kill "${d#/proc/}" 2>/dev/null || true ;;
  esac
done

WAV30="$PREFIX/drive_c/tone30.wav"
if [ ! -f "$WAV30" ]; then
  echo "missing $WAV30" >&2
  exit 1
fi
ls -l "$WAV30" "$PREFIX/drive_c/tone.wav"

# Stage the renderer where the PE32 harness LoadLibrary looks. Do not
# regsvr32 — Phase 1 uses DllGetClassObject only.
cp -f "$AX" "$PREFIX/drive_c/windows/system32/ss1waveout.ax"
cp -f "$AX" "$PREFIX/drive_c/ss1waveout.ax"
ls -l "$PREFIX/drive_c/windows/system32/ss1waveout.ax" "$PREFIX/drive_c/ss1waveout.ax"

export WINELOADER="$WINEELF"
export WINESERVER="${WINESERVER:-$WIN/bin/wineserver}"
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mshtml=d;ieframe=d"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err,+winmm}"
export BOX86_NOBANNER=1
export BOX86_LOG="${BOX86_LOG:-0}"
export BOX86_LD_LIBRARY_PATH="/media/fat/Windows/box86-extracted/usr/lib/box86-i386-linux-gnu:/media/fat/Windows/wine-installer/opt/wine-devel/lib:/media/fat/Windows/wine-installer/opt/wine-devel/lib/wine/i386-unix"
. "$WIN/bin/ss1-x11-env.sh"
. "$WIN/bin/ss1-winexe-gst-env.sh"
# Light GST: warnings only. Do not enable plugin/bus spam (previous OOM).
export GST_DEBUG="${GST_DEBUG:-1}"

mkdir -p "$WIN/logs"
: > "$LOG"
{
  echo "BOX86=$BOX86"
  echo "WINEPREFIX=$WINEPREFIX"
  echo "DISPLAY=$DISPLAY"
  echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
  echo "GST_PLUGIN_PATH=$GST_PLUGIN_PATH"
} | tee -a "$LOG"

echo "===== wine mem before ====="
[ -x "$WIN/bin/ss1-winexe-mem-wine.sh" ] && "$WIN/bin/ss1-winexe-mem-wine.sh" | tee -a "$LOG"
alsa before | tee -a "$LOG"

# Background; leave playing for physical listen. 30s WAV + Wine startup.
timeout 100 stdbuf -oL -eL "$BOX86" "$WINEELF" "$EXE" "C:\\tone30.wav" >>"$LOG" 2>&1 &
WPID=$!
echo $WPID > /tmp/ss1-wine.pid
echo "PLAYING pid=$WPID — leave this running for physical listen"
# wineboot can take ~15s; sample once playback should have started.
sleep 20
echo "===== wine mem t+20s =====" | tee -a "$LOG"
[ -x "$WIN/bin/ss1-winexe-mem-wine.sh" ] && "$WIN/bin/ss1-winexe-mem-wine.sh" | tee -a "$LOG"
alsa t+20s | tee -a "$LOG"
echo "===== cpu t+20s ====="
awk '/^cpu /{print}' /proc/stat
for d in /proc/[0-9]*; do
  c=$(cat "$d/comm" 2>/dev/null) || continue
  case "$c" in
    ss1-winexe-dsho|wine|wineserver|start.exe)
      pid=${d#/proc/}
      echo "proc $c pid=$pid utime=$(awk '{print $14,$15}' "$d/stat") rss=$(awk '/^VmRSS:/{print $2}' "$d/status")"
      ;;
  esac
done
echo "===== ss1wo t+20s =====" | tee -a "$LOG"
grep -E "SS1WO: (created|waveOutOpen|paused|first |playback released|STARVE|WOM_DONE|EndOfStream|EOS drained|EC_COMPLETE)|FILTER |force_ss1|graph has no|DURATION |STATE |BEFORE Run|^Run |POS i=0 |WAIT complete|DSHOW done|Sample dropped|Underrun of data" "$LOG" | tail -120 | tee /dev/stderr
echo "log=$LOG — harness still running; not waiting so the tone stays audible"
exit 0
