#!/bin/sh
# Snapshot the known-good ext4 Wine prefix image. Does not change FPGA,
# presenter, Xorg, or input. Stop Wine first so the copy is consistent.
set -e
WIN="${WIN:-/media/fat/Windows}"
IMG="${WINEPREFIX_IMG:-$WIN/wineprefix-prebuilt.ext4}"
TAG="${1:-pre-wmp9}"
DST="$WIN/wineprefix-prebuilt.ext4.bak-$TAG"

[ -f "$IMG" ] || { echo "missing $IMG" >&2; exit 1; }
if [ -x "$WIN/bin/ss1-winexe-stop-wine.sh" ]; then
  "$WIN/bin/ss1-winexe-stop-wine.sh" || true
fi
sync
if [ -f "$DST" ]; then
  echo "backup already exists: $DST"
  ls -l "$DST" "$IMG"
  exit 0
fi
echo "copy $IMG -> $DST"
cp -a "$IMG" "$DST"
sync
ls -l "$IMG" "$DST"
echo "restore: cp -a '$DST' '$IMG' && mount -o loop,noatime '$IMG' '${WINEPREFIX:-$WIN/wineprefix-prebuilt}'"
