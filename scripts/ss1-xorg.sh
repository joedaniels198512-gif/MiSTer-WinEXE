#!/bin/sh
# Start or stop the relocatable X.Org fbdev server on SuperStation One.
# Does not launch Wine. Does not install anything into /usr.
#
# Usage:
#   ss1-xorg.sh start
#   ss1-xorg.sh probe
#   ss1-xorg.sh stop
set -e

X11="${X11_ROOT:-/media/fat/Windows/x11}"
HOSTLIBS="${HOSTLIBS:-/media/fat/Windows/host-libs}"
DISPLAY_NUM="${DISPLAY_NUM:-0}"
export DISPLAY=":${DISPLAY_NUM}"

export LD_LIBRARY_PATH="$X11/lib${HOSTLIBS:+:$HOSTLIBS/lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$X11/bin:$PATH"
export XKB_CONFIG_ROOT="$X11/share/X11/xkb"
unset WAYLAND_DISPLAY

XORG="$X11/lib/xorg/Xorg"
[ -x "$XORG" ] || XORG="$X11/bin/Xorg"
LOG="${XORG_LOG:-/media/fat/Windows/logs/Xorg.${DISPLAY_NUM}.log}"
mkdir -p "$(dirname "$LOG")" /tmp/.X11-unix /tmp/bin /tmp/xorg.conf.d "$X11/etc/X11/xorg.conf.d"
# Xorg was patched to exec /tmp/bin/xkbcomp (not /usr/bin/xkbcomp).
# Remove any symlink first so we do not clobber x11/bin/xkbcomp.
# A precompiled keymap avoids Xorg's multi-word xkbcomp argv and -R vs -I.
rm -f /tmp/bin/xkbcomp
cat > /tmp/bin/xkbcomp <<EOF
#!/bin/sh
out=""
for out; do :; done
pre="$X11/share/X11/default.xkm"
if [ -f "\$pre" ] && [ -n "\$out" ] && [ "\$out" != "-" ]; then
  cp "\$pre" "\$out"
  exit 0
fi
export LD_LIBRARY_PATH="$X11/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PATH=/usr/bin:/bin
exec "$X11/bin/xkbcomp" -I"$X11/share/X11/xkb" "\$@"
EOF
chmod +x /tmp/bin/xkbcomp

xorg_running() {
  [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && kill -0 "$(cat /tmp/.X${DISPLAY_NUM}-lock 2>/dev/null | tr -d ' ')" 2>/dev/null
}

cmd_start() {
  if xorg_running; then
    echo "Xorg already running on :${DISPLAY_NUM}"
    return 0
  fi
  if [ ! -c /dev/fb0 ]; then
    echo "/dev/fb0 missing" >&2
    return 1
  fi
  if [ ! -x "$XORG" ]; then
    echo "Xorg missing at $XORG — deploy x11-runtime first" >&2
    return 1
  fi

  # Root, no logind, no VT grab beyond the existing framebuffer.
  "$XORG" ":${DISPLAY_NUM}" \
    -config "$X11/etc/X11/xorg.conf" \
    -configdir /tmp/xorg.conf.d \
    -modulepath "$X11/lib/xorg/modules" \
    -xkbdir "$X11/share/X11/xkb" \
    -logfile "$LOG" \
    -nolisten tcp \
    -noreset \
    -novtswitch \
    -sharevts \
    vt1 \
    >/dev/null 2>&1 &
  echo $! > /tmp/ss1-xorg.pid

    i=0
  while [ "$i" -lt 50 ]; do
    if ! kill -0 "$(cat /tmp/ss1-xorg.pid)" 2>/dev/null; then
      echo "Xorg exited during startup; see $LOG" >&2
      tail -40 "$LOG" >&2 || true
      return 1
    fi
    if [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]; then
      # Socket can appear before the server finishes (or crashes on XKB).
      sleep 0.4
      if kill -0 "$(cat /tmp/ss1-xorg.pid)" 2>/dev/null \
        && [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]; then
        echo "Xorg ready on :${DISPLAY_NUM} pid=$(cat /tmp/ss1-xorg.pid)"
        return 0
      fi
    fi
    i=$((i + 1))
    sleep 0.2
  done
  echo "Xorg socket did not appear; see $LOG" >&2
  tail -40 "$LOG" >&2 || true
  return 1
}

cmd_stop() {
  if [ -f /tmp/ss1-xorg.pid ]; then
    kill "$(cat /tmp/ss1-xorg.pid)" 2>/dev/null || true
    rm -f /tmp/ss1-xorg.pid
  fi
  if [ -f "/tmp/.X${DISPLAY_NUM}-lock" ]; then
    lockpid=$(tr -d ' ' < "/tmp/.X${DISPLAY_NUM}-lock")
    kill "$lockpid" 2>/dev/null || true
    sleep 1
    kill -9 "$lockpid" 2>/dev/null || true
  fi
  # Do not pkill broadly; only leftover Xorg from this tree.
  for pid in $(ps | awk '/[X]org/ {print $1}'); do
    kill "$pid" 2>/dev/null || true
  done
  rm -f "/tmp/.X${DISPLAY_NUM}-lock"
  echo "Xorg stopped"
}

cmd_probe() {
  cmd_start
  echo "===== xset q ====="
  "$X11/bin/xset" q
  echo "===== xsetroot ====="
  "$X11/bin/xsetroot" -solid gray20 || true
  echo "PROBE_OK display=$DISPLAY"
}

case "${1:-start}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  probe) cmd_probe ;;
  *)
    echo "usage: $0 start|probe|stop" >&2
    exit 2
    ;;
esac
