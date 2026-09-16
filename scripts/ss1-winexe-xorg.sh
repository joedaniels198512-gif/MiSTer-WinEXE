#!/bin/sh
# Start Xorg with the dummy driver at 640x480 for WinEXE_Test.
# Does not use /dev/fb0. Does not launch Wine.
set -e

WIN="${WIN:-/media/fat/Windows}"
X11="${X11_ROOT:-$WIN/x11}"
HOSTLIBS="${HOSTLIBS:-$WIN/host-libs}"
DISPLAY_NUM="${DISPLAY_NUM:-0}"
export DISPLAY=":${DISPLAY_NUM}"

export LD_LIBRARY_PATH="$X11/lib${HOSTLIBS:+:$HOSTLIBS/lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$X11/bin:$PATH"
export XKB_CONFIG_ROOT="$X11/share/X11/xkb"
unset WAYLAND_DISPLAY

XORG="$X11/lib/xorg/Xorg"
[ -x "$XORG" ] || XORG="$X11/bin/Xorg"
LOG="${XORG_LOG:-$WIN/logs/Xorg.winexe.log}"
CONF="${XORG_WINEXE_CONF:-$WIN/x11/etc/X11/xorg.winexe.conf}"
mkdir -p "$(dirname "$LOG")" /tmp/.X11-unix /tmp/bin /tmp/xorg.conf.d "$X11/etc/X11"

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
  if [ ! -f "$X11/lib/xorg/modules/drivers/dummy_drv.so" ]; then
    echo "dummy_drv.so missing under $X11 — deploy the WinEXE presenter artifact first" >&2
    return 1
  fi
  if [ ! -f "$CONF" ]; then
    echo "missing $CONF" >&2
    return 1
  fi
  if xorg_running; then
    echo "Xorg already running on :${DISPLAY_NUM}"
    return 0
  fi
  if [ ! -x "$XORG" ]; then
    echo "Xorg missing at $XORG" >&2
    return 1
  fi

  STDOUT_LOG="${XORG_STDOUT_LOG:-$WIN/logs/xorg-winexe-stdout.log}"
  setsid "$XORG" ":${DISPLAY_NUM}" \
    -config "$CONF" \
    -configdir /tmp/xorg.conf.d \
    -modulepath "$X11/lib/xorg/modules" \
    -xkbdir "$X11/share/X11/xkb" \
    -logfile "$LOG" \
    -nolisten tcp \
    -noreset \
    -novtswitch \
    -sharevts \
    vt1 \
    </dev/null >>"$STDOUT_LOG" 2>&1 &
  echo $! > /tmp/ss1-xorg.pid

  i=0
  while [ "$i" -lt 50 ]; do
    if ! kill -0 "$(cat /tmp/ss1-xorg.pid)" 2>/dev/null; then
      echo "Xorg exited during startup; see $LOG" >&2
      tail -40 "$LOG" >&2 || true
      return 1
    fi
    if [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]; then
      sleep 0.4
      if kill -0 "$(cat /tmp/ss1-xorg.pid)" 2>/dev/null \
        && [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]; then
        echo "Xorg dummy ready on :${DISPLAY_NUM} pid=$(cat /tmp/ss1-xorg.pid)"
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
  "$WIN/bin/ss1-xorg.sh" stop
}

case "${1:-start}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  *)
    echo "usage: $0 start|stop" >&2
    exit 2
    ;;
esac
