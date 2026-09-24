#!/bin/sh
# Direct PAL8 prototype helper. Profile-only; does not change the launcher.
#
#   ss1-cnc-pal8.sh start   — inject hook after C&C is up
#   ss1-cnc-pal8.sh stop    — clear mailbox → FPGA BGRX, presenter resumes
set -e
WIN="${WIN:-/media/fat/games/WinEXE}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
CMD="${1:-start}"
INJECT="$WIN/apps/diag/ss1-cnc-pal8.exe"

pal8_off() {
  python3 - << 'PY'
import mmap, os, struct
PHYS, SIZE, MAGIC = 0x30400000, 4096, 0x50384C38
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
mm = mmap.mmap(fd, SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=PHYS)
magic, flags = struct.unpack_from("<II", mm, 0)
if magic == MAGIC:
    struct.pack_into("<I", mm, 4, 0)
    print("cnc-pal8: mailbox pal8_en=0 (BGRX fallback)")
else:
    print("cnc-pal8: mailbox magic 0x%08x (left untouched)" % magic)
mm.close()
os.close(fd)
PY
  rm -f /tmp/ss1-pal8.active
}

case "$CMD" in
  stop)
    pal8_off
    ;;
  start)
    if [ ! -f "$INJECT" ]; then
      echo "cnc-pal8: injector missing ($INJECT); C&C stays on Wine/X"
      exit 0
    fi
    export HOME="${HOME:-/root}"
    export DISPLAY="${DISPLAY:-:0}"
    export WINEPREFIX="$PREFIX"
    export WINEARCH=win32
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
    export WINEDEBUG="${WINEDEBUG:--all}"
    winebin="$WIN/bin/wine"
    [ -x "$winebin" ] || winebin=wine
    echo "cnc-pal8: injecting $INJECT"
    setsid "$winebin" start /unix "$INJECT" \
      </dev/null >/tmp/ss1-cnc-pal8-wine.log 2>&1 &
    ;;
  *)
    echo "usage: ss1-cnc-pal8.sh start|stop" >&2
    exit 1
    ;;
esac
