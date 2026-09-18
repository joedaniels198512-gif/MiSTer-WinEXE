#!/bin/sh
# Cross-compile Direct PAL8 ARM + (optional) mingw guest hook.
# Does not start Quartus.
set -e
REPO=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
OUT="${1:-$REPO}"
ARM="${ARM_CC:-arm-linux-gnueabihf-gcc}"
MINGW="${MINGW_CC:-i686-w64-mingw32-gcc}"

echo "ARM_CC=$ARM"
"$ARM" -O2 -Wall -fPIC -shared -pthread \
  -o "$OUT/ss1-pal8-map.so" "$REPO/scripts/ss1-pal8-map.c"
echo "built $OUT/ss1-pal8-map.so"

if command -v "${MINGW%% *}" >/dev/null 2>&1 || command -v i686-w64-mingw32-gcc >/dev/null 2>&1; then
  CC="$MINGW"
  command -v "$CC" >/dev/null 2>&1 || CC=i686-w64-mingw32-gcc
  "$CC" -O2 -Wall -shared -o "$OUT/ss1-cnc-pal8.dll" \
    "$REPO/scripts/ss1-cnc-pal8-hook.c" -static-libgcc
  "$CC" -O2 -Wall -s -mwindows -o "$OUT/ss1-cnc-pal8.exe" \
    "$REPO/scripts/ss1-cnc-pal8.c" -static-libgcc
  echo "built $OUT/ss1-cnc-pal8.dll $OUT/ss1-cnc-pal8.exe"
else
  echo "mingw not present; guest hook sources are ready (ss1-cnc-pal8-hook.c / ss1-cnc-pal8.c)"
fi
