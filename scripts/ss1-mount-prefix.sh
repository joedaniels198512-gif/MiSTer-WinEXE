#!/bin/sh
# Loop-mount the ext4 Wine prefix image. exFAT cannot store prefix symlinks.
# Does not format or recreate the image. Does not touch /usr.
set -e
IMG="${WINEPREFIX_IMG:-/media/fat/games/WinEXE/wineprefix-prebuilt.ext4}"
MNT="${WINEPREFIX:-/media/fat/games/WinEXE/wineprefix-prebuilt}"

if mount | grep -q " on ${MNT} "; then
  echo "already mounted: $MNT"
  exit 0
fi
[ -f "$IMG" ] || { echo "missing $IMG" >&2; exit 1; }
mkdir -p "$MNT"
mount -o loop,noatime "$IMG" "$MNT"
echo "mounted $IMG -> $MNT"
mount | grep " on ${MNT} "
