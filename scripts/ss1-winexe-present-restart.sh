#!/bin/sh
# Restart only ss1-winexe-x11-present. Does not touch FPGA, Xorg, Wine, or input.
# Env: SS1_HZ (default 60), SS1_SKIP_UNCHANGED (default 1),
#      SS1_CURSOR_ONLY (default 1), SS1_DIRTY, SS1_TILE_W, SS1_TILE_H,
#      SS1_DIRTY_PCT, SS1_FRAME_US, SS1_XSYNC, SS1_OSYNC
set -e
WIN="${WIN:-/media/fat/Windows}"
LOGDIR="$WIN/logs"
PRESLOG="${SS1_PRESENT_LOG:-$LOGDIR/ss1-winexe-x11-present.log}"

[ -S /tmp/.X11-unix/X0 ] || { echo "dummy Xorg :0 not running" >&2; exit 1; }
[ -x "$WIN/bin/ss1-winexe-x11-present" ] || { echo "missing presenter" >&2; exit 1; }

if [ -f /tmp/ss1-winexe-x11-present.pid ]; then
  kill "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null || true
  rm -f /tmp/ss1-winexe-x11-present.pid
fi
# comm is truncated to ss1-winexe-x11-
for d in /proc/[0-9]*; do
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  case "$comm" in
    ss1-winexe-x11-*) kill "${d#/proc/}" 2>/dev/null || true ;;
  esac
done
sleep 1

export DISPLAY="${DISPLAY:-:0}"
export LD_LIBRARY_PATH="$WIN/x11/lib:$WIN/host-libs/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export SS1_HZ="${SS1_HZ:-60}"
export SS1_SKIP_UNCHANGED="${SS1_SKIP_UNCHANGED:-1}"
export SS1_CURSOR_ONLY="${SS1_CURSOR_ONLY:-1}"
export SS1_DIRTY="${SS1_DIRTY:-0}"
export SS1_TILE_W="${SS1_TILE_W:-32}"
export SS1_TILE_H="${SS1_TILE_H:-32}"
export SS1_DIRTY_PCT="${SS1_DIRTY_PCT:-60}"

mkdir -p "$LOGDIR"
echo "===== restart hz=$SS1_HZ skip=$SS1_SKIP_UNCHANGED cursor_only=$SS1_CURSOR_ONLY dirty=$SS1_DIRTY tile=${SS1_TILE_W}x${SS1_TILE_H} pct=$SS1_DIRTY_PCT $(date) =====" >>"$PRESLOG"
setsid "$WIN/bin/ss1-winexe-x11-present" </dev/null >>"$PRESLOG" 2>&1 &
echo $! > /tmp/ss1-winexe-x11-present.pid
sleep 1
if ! kill -0 "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null; then
  echo "presenter exited; see $PRESLOG" >&2
  tail -20 "$PRESLOG" >&2 || true
  exit 1
fi
echo "presenter_ok pid=$(cat /tmp/ss1-winexe-x11-present.pid) hz=$SS1_HZ skip=$SS1_SKIP_UNCHANGED cursor_only=$SS1_CURSOR_ONLY dirty=$SS1_DIRTY tile=${SS1_TILE_W}x${SS1_TILE_H}"
