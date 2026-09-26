#!/bin/sh
# Installer-only prefix preparation. Never format an existing image or extract
# a symlink-bearing Wine prefix directly onto the SD filesystem.
set -eu
WIN=${1:?runtime directory}
OLDWIN=${2:?legacy runtime directory}
IMG="$WIN/wineprefix-prebuilt.ext4"
MNT="$WIN/wineprefix-prebuilt"
ARCHIVE="$WIN/wineprefix-prebuilt.tar.xz"
NEW=""
NEW_MOUNTED=0

fail() { echo "ERROR: $*" >&2; exit 1; }
mounted() { mountpoint -q "$1"; }
valid() { [ -f "$MNT/system.reg" ] && [ -f "$MNT/user.reg" ] && [ -d "$MNT/dosdevices" ]; }
cleanup() {
  if [ "$NEW_MOUNTED" = 1 ] && mounted "$MNT"; then
    if ! umount "$MNT"; then
      echo "ERROR: cannot unmount $MNT; image ${NEW:-$IMG} retained. Resolve this mount before retrying; do not delete its backing file." >&2
      return 0
    fi
  fi
  [ -z "$NEW" ] || rm -f "$NEW"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

for old in "$OLDWIN"/wineprefix*; do
  if [ -e "$old" ] || [ -L "$old" ]; then
    fail "Legacy prefix found in $OLDWIN. Automatic migration is not currently performed; migration will be handled separately. Old prefix untouched."
  fi
done
command -v mountpoint >/dev/null || fail "mountpoint is required"
# Never mistake an interrupted extraction for a completed prefix.
for pending in "$WIN"/.wineprefix-new.*; do
  if [ -e "$pending" ] || [ -L "$pending" ]; then
    fail "Interrupted installation image retained: $pending. Inspect/unmount $MNT and recover or remove this temporary image explicitly before retrying."
  fi
done
if mounted "$MNT"; then
  valid || fail "mounted prefix is incomplete; left untouched: $MNT"
  echo "prefix: existing mounted prefix preserved"
  exit 0
fi
if [ -f "$IMG" ]; then
  # Never hide data in a nonempty mount point or replace an invalid image.
  [ ! -d "$MNT" ] || [ -z "$(ls -A "$MNT")" ] || fail "unmounted prefix directory contains data: $MNT"
  mkdir -p "$MNT"
  NEW_MOUNTED=1
  mount -o loop,noatime "$IMG" "$MNT" || fail "cannot mount existing prefix; left untouched: $IMG"
  valid || fail "existing prefix is incomplete; repair it separately: $IMG"
  NEW_MOUNTED=0
  echo "prefix: existing image preserved and mounted"
  exit 0
fi
if [ -d "$MNT" ] && [ -n "$(ls -A "$MNT")" ]; then
  valid || fail "prefix directory contains incomplete/user data; left untouched: $MNT"
  # Preserve a working directory prefix on a symlink-capable filesystem.
  fs=$(stat -f -c %T "$MNT")
  case "$fs" in exfat|vfat|msdos|fuseblk) fail "directory prefix on $fs needs explicit migration to ext4" ;; esac
  echo "prefix: existing directory preserved"
  exit 0
fi

mkdir -p "$MNT"
[ -f "$ARCHIVE" ] || fail "missing clean prefix archive: $ARCHIVE"
for cmd in mkfs.ext4 dd tar mount umount python3; do
  command -v "$cmd" >/dev/null || fail "missing prefix installation tool: $cmd"
done
python3 "$WIN/bin/ss1-winexe-verify-package.py" "$ARCHIVE" --prefix-only
MB=${WINEXE_PREFIX_MB:-512}
case "$MB" in ''|*[!0-9]*) fail "WINEXE_PREFIX_MB must be an integer" ;; esac
[ "$MB" -ge 256 ] || fail "WINEXE_PREFIX_MB must be at least 256"
python3 "$WIN/bin/ss1-winexe-verify-package.py" "$ARCHIVE" --prefix-only --image-mb "$MB" --space-dir "$WIN"
NEW=$(mktemp "$WIN/.wineprefix-new.XXXXXX")
# Allocate real space: exFAT does not support sparse files. Format only our
# newly-created temporary file; disable features unsupported by older kernels.
dd if=/dev/zero of="$NEW" bs=1048576 count="$MB"
mkfs.ext4 -q -F -O '^64bit,^metadata_csum' "$NEW"
NEW_MOUNTED=1
mount -o loop,noatime "$NEW" "$MNT" || fail "cannot mount new prefix image"
tar -xJf "$ARCHIVE" -C "$MNT" --strip-components=1
valid || fail "clean prefix archive is incomplete"
# Only a new prefix is retargeted. Existing registries and links stay intact.
find "$MNT" -type l | while IFS= read -r link; do
  target=$(readlink "$link")
  case "$target" in
    /media/fat/Windows/*)
      ln -sfn "/media/fat/games/WinEXE/${target#/media/fat/Windows/}" "$link" ;;
  esac
done
sync
umount "$MNT"
NEW_MOUNTED=0
mv "$NEW" "$IMG"
NEW=""
NEW_MOUNTED=1
mount -o loop,noatime "$IMG" "$MNT" || fail "prefix created but remount failed: $IMG"
echo "prefix: created and mounted ${MB} MiB ext4 image"
NEW_MOUNTED=0
