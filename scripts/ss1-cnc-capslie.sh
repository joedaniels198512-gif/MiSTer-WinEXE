#!/bin/sh
# In-memory C&C95 GetCaps lie + vblank skip. Profile-only; does not patch the EXE.
# Start this BEFORE C&C so the plant wins the race against primary GetCaps
# (Wine reports DDSCAPS_SYSTEMMEMORY → MessageBox "Unable to allocate primary surface").
#
#   ss1-cnc-capslie.sh start   — waiter; plants then exits
#   ss1-cnc-capslie.sh stop    — no-op (waiter is already gone)
set -e
WIN="${WIN:-/media/fat/games/WinEXE}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
CMD="${1:-start}"
EXE="$WIN/apps/diag/ss1-cnc-capslie.exe"

case "$CMD" in
  stop)
    ;;
  start)
    if [ ! -f "$EXE" ]; then
      echo "cnc-capslie: missing $EXE; C&C may show primary-surface MessageBox"
      exit 0
    fi
    export HOME="${HOME:-/root}"
    export DISPLAY="${DISPLAY:-:0}"
    export WINEPREFIX="$PREFIX"
    export WINEARCH=win32
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
    export WINEDEBUG="${WINEDEBUG:--all}"
    if [ -f "$WIN/bin/ss1-x11-env.sh" ]; then
      # shellcheck disable=SC1091
      . "$WIN/bin/ss1-x11-env.sh"
    fi
    winebin="$WIN/bin/wine"
    [ -x "$winebin" ] || winebin=wine
    rm -f /tmp/ss1-cnc-capslie.log
    echo "cnc-capslie: waiting to plant $EXE"
    setsid "$winebin" start /unix "$EXE" \
      </dev/null >/tmp/ss1-cnc-capslie-wine.log 2>&1 &
    ;;
  *)
    echo "usage: ss1-cnc-capslie.sh start|stop" >&2
    exit 1
    ;;
esac
