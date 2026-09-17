#!/bin/sh
# Launch a user-supplied 32-bit Windows PE from /media/fat/Windows/apps/
# (or an explicit path) on SuperStation One.
#
# Does not modify Box86, Wine, or Xorg. Reuses the existing wrapper,
# prefix, and display stack. Keeps Xorg if it is already running.
#
# Usage:
#   ss1-run-exe.sh notepad.exe
#   ss1-run-exe.sh /media/fat/Windows/apps/mspaint.exe
#   ss1-run-exe.sh --inspect notepad.exe
#
# Options:
#   --inspect   PE32 check only; do not launch
#   --no-desktop  do not wrap in explorer /desktop=ss1,WxH
set -e
WIN=/media/fat/Windows
APPS="$WIN/apps"
LOGDIR="$WIN/logs/apps"
DESKTOP="${SS1_DESKTOP:-1024x768}"
INSPECT_ONLY=0
USE_DESKTOP=1

while [ $# -gt 0 ]; do
  case "$1" in
    --inspect) INSPECT_ONLY=1; shift ;;
    --no-desktop) USE_DESKTOP=0; shift ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

if [ $# -lt 1 ]; then
  echo "usage: $0 [--inspect] [--no-desktop] <exe> [args...]" >&2
  echo "drop PE32 files in $APPS" >&2
  exit 2
fi

EXE=$1
shift
case "$EXE" in
  /*) ;;
  *)
    if [ -f "$EXE" ]; then
      EXE=$(cd "$(dirname "$EXE")" && pwd)/$(basename "$EXE")
    elif [ -f "$APPS/$EXE" ]; then
      EXE="$APPS/$EXE"
    else
      echo "not found: $EXE (also tried $APPS/$EXE)" >&2
      exit 1
    fi
    ;;
esac
[ -f "$EXE" ] || { echo "not a file: $EXE" >&2; exit 1; }

mkdir -p "$APPS" "$LOGDIR"
STEM=$(basename "$EXE" | tr 'A-Z' 'a-z')
STEM=${STEM%.exe}

PE_INFO=$(python3 - "$EXE" << 'PY'
import os, struct, sys
path = sys.argv[1]
with open(path, "rb") as f:
    data = f.read(4096)
if len(data) < 64 or data[:2] != b"MZ":
    print("NOT_PE reason=no_mz")
    sys.exit(0)
e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
if e_lfanew + 0x5C > len(data):
    with open(path, "rb") as f:
        data = f.read(e_lfanew + 0x80)
if data[e_lfanew:e_lfanew+4] != b"PE\0\0":
    print("NOT_PE reason=no_pe")
    sys.exit(0)
machine = struct.unpack_from("<H", data, e_lfanew + 4)[0]
opt = struct.unpack_from("<H", data, e_lfanew + 0x18)[0]
subsystem = struct.unpack_from("<H", data, e_lfanew + 0x5C)[0]
size = os.path.getsize(path)
mach = {0x14C: "i386", 0x8664: "x86_64", 0x1C0: "arm", 0xAA64: "arm64"}.get(machine, "0x%04x" % machine)
kind = {0x10B: "PE32", 0x20B: "PE32+"}.get(opt, "opt=0x%04x" % opt)
sub = {1: "native", 2: "gui", 3: "cui"}.get(subsystem, "sub=%d" % subsystem)
ok = "yes" if machine == 0x14C and opt == 0x10B else "no"
print("ok=%s kind=%s machine=%s subsystem=%s bytes=%d path=%s" % (ok, kind, mach, sub, size, path))
PY
)
echo "$PE_INFO"
case "$PE_INFO" in
  ok=yes*) ;;
  *)
    echo "refusing launch: need genuine x86 PE32 (i386)" >&2
    exit 1
    ;;
esac

if [ "$INSPECT_ONLY" = 1 ]; then
  exit 0
fi

"$WIN/bin/ss1-mount-prefix.sh"
export WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
export WINEARCH=win32
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err}"
export BOX86_LOG="${BOX86_LOG:-1}"
export BOX86_NOBANNER="${BOX86_NOBANNER:-0}"
. "$WIN/bin/ss1-x11-env.sh"

if [ ! -f /tmp/ss1-xorg.pid ] || ! kill -0 "$(cat /tmp/ss1-xorg.pid)" 2>/dev/null; then
  "$WIN/bin/ss1-xorg.sh" start
  "$WIN/x11/bin/xset" s off -dpms >/dev/null 2>&1 || true
  "$WIN/x11/bin/xsetroot" -solid navy >/dev/null 2>&1 || true
fi
if [ ! -f /tmp/ss1-present.pid ] || ! kill -0 "$(cat /tmp/ss1-present.pid)" 2>/dev/null; then
  export SS1_PRESENT_LOG="$WIN/logs/ss1-present.log"
  mkdir -p "$WIN/logs"
  setsid /bin/sh -c "exec $WIN/bin/ss1-fb-present.sh loop 0" </dev/null >>"$SS1_PRESENT_LOG" 2>&1 &
  echo $! > /tmp/ss1-present.pid
fi

# Replace the previous Windows app; leave Xorg/presenter alone.
if [ -x "$WIN/bin/ss1-winexe-stop-wine.sh" ]; then
  "$WIN/bin/ss1-winexe-stop-wine.sh"
else
  if [ -f /tmp/ss1-wine.pid ]; then
    kill "$(cat /tmp/ss1-wine.pid)" 2>/dev/null || true
  fi
  "$WIN/bin/wineserver" -k 2>/dev/null || true
  sleep 1
fi

STAMP=$(date +%Y%m%d_%H%M%S)
LOG="$LOGDIR/${STEM}.log"
HIST="$LOGDIR/${STEM}-${STAMP}.log"
{
  echo "===== $STAMP ====="
  echo "exe=$EXE"
  echo "$PE_INFO"
  echo "desktop=$USE_DESKTOP $DESKTOP"
  echo "WINEPREFIX=$WINEPREFIX DISPLAY=$DISPLAY"
} > "$LOG"
cp "$LOG" "$HIST"

if [ "$USE_DESKTOP" = 1 ]; then
  set -- explorer "/desktop=ss1,$DESKTOP" "$EXE" "$@"
else
  set -- "$EXE" "$@"
fi

setsid /bin/sh -c "exec $WIN/bin/wine \"\$@\"" _ "$@" </dev/null >>"$LOG" 2>&1 &
echo $! > /tmp/ss1-wine.pid
echo "$EXE" > /tmp/ss1-wine.exe
echo "LAUNCHED pid=$(cat /tmp/ss1-wine.pid) exe=$EXE"
echo "log=$LOG"
echo "copy=$HIST"
