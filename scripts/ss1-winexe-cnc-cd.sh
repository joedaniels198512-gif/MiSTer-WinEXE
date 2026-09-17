#!/bin/sh
# Mount the stock C&C Gold Nod ISO as Wine drive D: (CD-ROM).
# Generic helper invoked from profiles/cnc.ini. Does not change the launcher.
#
#   ss1-winexe-cnc-cd.sh start
#   ss1-winexe-cnc-cd.sh stop
set -e
WIN="${WIN:-/media/fat/Windows}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
ISO="${SS1_CNC_ISO:-$WIN/iso/CnC_NOD95.iso}"
MNT="${SS1_CNC_MNT:-/tmp/ss1-cnc-cd}"
CMD="${1:-start}"

mounted() {
  awk -v m="$MNT" '$2 == m { found=1 } END { exit found ? 0 : 1 }' /proc/mounts
}

loop_for_mnt() {
  awk -v m="$MNT" '$2 == m { print $1; exit }' /proc/mounts
}

# Register D: with the running wineserver as a CD-ROM so GetDriveType
# stays DRIVE_CDROM and GetVolumeInformation can read the ISO label.
# Loop-mounted ISO otherwise leaves mountmgr unaware; volume queries then
# return ERROR_INVALID_FUNCTION and C&C rejects the disc.
mark_wine_cdrom() {
  probe="$WIN/apps/diag/ss1-cnc-cdprobe.exe"
  winebin="$WIN/bin/wine"
  loop=$(loop_for_mnt)
  device="$loop"
  [ -n "$device" ] && [ -e "$device" ] || device="$ISO"
  if [ ! -f "$probe" ] || [ ! -x "$winebin" ]; then
    echo "cnc-cd: skip mountmgr mark (probe or wine missing)"
    return 0
  fi
  export HOME="${HOME:-/root}"
  export DISPLAY="${DISPLAY:-:0}"
  export WINEPREFIX="$PREFIX"
  export WINEARCH=win32
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
  if [ -f "$WIN/bin/ss1-x11-env.sh" ]; then
    # shellcheck disable=SC1091
    . "$WIN/bin/ss1-x11-env.sh"
  fi
  echo "cnc-cd: mountmgr DEFINE D: mount=$MNT device=$device"
  WINEDEBUG=-all "$winebin" "$probe" --set-cdrom D "$MNT" "$device" || \
    echo "cnc-cd: mountmgr mark failed" >&2
}

attach_wine_d() {
  mkdir -p "$PREFIX/dosdevices"
  ln -sfn "$MNT" "$PREFIX/dosdevices/d:"
  loop=$(loop_for_mnt)
  if [ -n "$loop" ] && [ -e "$loop" ]; then
    ln -sfn "$loop" "$PREFIX/dosdevices/d::"
  elif [ -f "$ISO" ]; then
    ln -sfn "$ISO" "$PREFIX/dosdevices/d::"
  else
    rm -f "$PREFIX/dosdevices/d::"
  fi
  echo "cnc-cd: D: -> $MNT (${loop:-no-loop})"
  mark_wine_cdrom
}

case "$CMD" in
  start)
    [ -f "$ISO" ] || { echo "missing C&C ISO: $ISO" >&2; exit 1; }
    mkdir -p "$MNT"
    if ! mounted; then
      mount -o loop,ro "$ISO" "$MNT"
    fi
    attach_wine_d
    ;;
  stop)
    rm -f "$PREFIX/dosdevices/d:" "$PREFIX/dosdevices/d::"
    if mounted; then
      umount "$MNT" || umount -l "$MNT" || true
    fi
    echo "cnc-cd: unmounted"
    ;;
  status)
    if mounted; then
      echo "mounted $MNT iso=$ISO loop=$(loop_for_mnt)"
      ls -l "$PREFIX/dosdevices/d:" "$PREFIX/dosdevices/d::" 2>/dev/null || true
    else
      echo "not mounted"
    fi
    ;;
  *)
    echo "usage: $0 start|stop|status" >&2
    exit 1
    ;;
esac
