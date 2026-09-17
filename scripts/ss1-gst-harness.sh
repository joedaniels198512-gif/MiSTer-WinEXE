#!/bin/sh
# Run the i386 GStreamer harness through Box86 with the WMP-private ARMHF
# GStreamer env. No Wine, no X11, no WMP, no audio.
set +e
WIN="${WIN:-/media/fat/Windows}"
BOX86="${BOX86:-$WIN/box86-ss1/box86}"
HARNESS="${HARNESS:-$WIN/bin/ss1-gst-harness}"
LOG="${LOG:-$WIN/logs/ss1-gst-harness.log}"
STAGE="${SS1_GST_STAGE:-find}"

mem() {
  awk '/^MemAvailable:/{a=$2} /^AnonPages:/{n=$2} END{printf "MemAvailable=%s AnonPages=%s\n", a, n}' /proc/meminfo
}

echo "===== before ====="
mem
"$BOX86" -v 2>&1 | head -3
ls -l "$HARNESS" "$BOX86"
file "$HARNESS" 2>/dev/null

. "$WIN/bin/ss1-winexe-gst-env.sh"
export BOX86_LOG="${BOX86_LOG:-1}"
export GST_DEBUG="${GST_DEBUG:-GST_PLUGIN_LOADING:4,GST_ELEMENT_FACTORY:4,GST_PLUGIN:3}"
# Keep scanner from forking inside Box86 (same as WMP env).
export GST_REGISTRY_FORK=no
export GST_REGISTRY_UPDATE=no

mkdir -p "$WIN/logs"
: > "$LOG"
echo "BOX86=$BOX86 STAGE=$STAGE" | tee -a "$LOG"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH" | tee -a "$LOG"
echo "GST_PLUGIN_PATH=$GST_PLUGIN_PATH" | tee -a "$LOG"
echo "GST_REGISTRY=$GST_REGISTRY" | tee -a "$LOG"

# Line-buffered; log on /media/fat, not a huge RAM pipe.
timeout 40 stdbuf -oL -eL "$BOX86" "$HARNESS" "$STAGE" >>"$LOG" 2>&1
rc=$?
echo "===== after rc=$rc ====="
mem
echo "log=$LOG bytes=$(wc -c < "$LOG")"
grep -E 'HARNESS |BEFORE |AFTER |OK |FAIL |native\(wrapped\)|libgtk|Error initializing|segmentation|plugin file' "$LOG" | head -80
exit $rc
