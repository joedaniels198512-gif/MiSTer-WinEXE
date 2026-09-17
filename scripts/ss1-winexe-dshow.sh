#!/bin/sh
# Stage 1: minimal Wine DirectShow PCM WAV graph via box86-gstflow.
# Does not launch WMP. Does not overwrite original Box86.
set +e
WIN="${WIN:-/media/fat/Windows}"
BOX86="${BOX86:-$WIN/box86-ss1/box86-gstflow}"
WINEELF="$WIN/wine-installer/opt/wine-devel/bin/wine"
EXE="${EXE:-$WIN/bin/ss1-winexe-dshow.exe}"
LOG="${LOG:-$WIN/logs/ss1-winexe-dshow.log}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"

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
ls -l "$BOX86" "$WIN/box86-ss1/box86" "$EXE" 2>/dev/null
"$BOX86" -v 2>&1 | head -2

[ -x "$BOX86" ] || { echo "missing $BOX86" >&2; exit 1; }
[ -x "$WINEELF" ] || { echo "missing $WINEELF" >&2; exit 1; }
[ -f "$EXE" ] || { echo "missing $EXE" >&2; exit 1; }
[ -x "$WIN/box86-ss1/box86" ] || { echo "original box86 missing" >&2; exit 1; }

"$WIN/bin/ss1-mount-prefix.sh" || exit 1
export WINEPREFIX="$PREFIX"
export WINEARCH=win32

# Dummy Xorg for Wine window station only. Do not start FPGA presenter (core may be MENU).
if [ -x "$WIN/bin/ss1-winexe-xorg.sh" ]; then
  "$WIN/bin/ss1-winexe-xorg.sh" start || true
fi

"$WIN/bin/ss1-winexe-stop-wine.sh"

if [ -f /tmp/tone.wav ] && [ ! -f "$PREFIX/drive_c/tone.wav" ]; then
  cp -a /tmp/tone.wav "$PREFIX/drive_c/tone.wav"
fi
ls -l "$PREFIX/drive_c/tone.wav"

export WINELOADER="$WINEELF"
export WINESERVER="${WINESERVER:-$WIN/bin/wineserver}"
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mshtml=d;ieframe=d"
export WINEDEBUG="${WINEDEBUG:-+err}"
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

# Background so we can sample ALSA while the 3s tone runs.
timeout 20 stdbuf -oL -eL "$BOX86" "$WINEELF" "$EXE" >>"$LOG" 2>&1 &
WPID=$!
echo $WPID > /tmp/ss1-wine.pid
sleep 2
echo "===== wine mem t+2s =====" | tee -a "$LOG"
[ -x "$WIN/bin/ss1-winexe-mem-wine.sh" ] && "$WIN/bin/ss1-winexe-mem-wine.sh" | tee -a "$LOG"
alsa t+2s | tee -a "$LOG"
wait $WPID
rc=$?

echo "===== after rc=$rc ====="
mem
alsa after
echo "log=$LOG bytes=$(wc -c < "$LOG")"
grep -E 'DSHOW |WaveParser|FilterGraph|RenderFile|FILTER |DURATION |STATE |POS |Run |WAIT |hr=|Error|err:|fixme:gstreamer|winegstreamer|native\(wrapped\) libgst' "$LOG" | head -80
exit $rc
