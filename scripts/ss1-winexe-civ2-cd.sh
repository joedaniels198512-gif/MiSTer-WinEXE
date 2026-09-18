#!/bin/sh
# Mount the Civ II MGE data-track ISO as Wine drive D: (CD-ROM).
# Audio tracks stay in the original BIN/CUE set. PCM copies for the
# Civ II MCI shim are prepared under apps/civ2/cdaudio/ (not the BIN/CUE).
#
#   ss1-winexe-civ2-cd.sh start
#   ss1-winexe-civ2-cd.sh stop
set -e
WIN="${WIN:-/media/fat/Windows}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
ISO="${SS1_CIV2_ISO:-$WIN/iso/Civ2_MGE.iso}"
MNT="${SS1_CIV2_MNT:-/tmp/ss1-civ2-cd}"
CMD="${1:-start}"

mounted() {
  awk -v m="$MNT" '$2 == m { found=1 } END { exit found ? 0 : 1 }' /proc/mounts
}

loop_for_mnt() {
  awk -v m="$MNT" '$2 == m { print $1; exit }' /proc/mounts
}

mark_wine_cdrom() {
  probe="$WIN/apps/diag/ss1-cnc-cdprobe.exe"
  winebin="$WIN/bin/wine"
  loop=$(loop_for_mnt)
  device="$loop"
  [ -n "$device" ] && [ -e "$device" ] || device="$ISO"
  if [ ! -f "$probe" ] || [ ! -x "$winebin" ]; then
    echo "civ2-cd: skip mountmgr mark (probe or wine missing)"
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
  echo "civ2-cd: mountmgr DEFINE D: mount=$MNT device=$device"
  WINEDEBUG=-all "$winebin" "$probe" --set-cdrom D "$MNT" "$device" || \
    echo "civ2-cd: mountmgr mark failed" >&2
}

VIDOV="${SS1_CIV2_VIDEO_VFW:-$WIN/apps/civ2/video-vfw}"
VIDMNT="$MNT/CIV2/VIDEO"
VIDLOWER=/tmp/ss1-civ2-video-lower
VIDWORK=/tmp/ss1-civ2-video-work
VIDHDD="$WIN/apps/civ2/video"
VIDNEST="$WIN/apps/civ2/civ2/video"

unmount_hdd_video() {
  umount "$VIDHDD" 2>/dev/null || umount -l "$VIDHDD" 2>/dev/null || true
  umount "$VIDNEST" 2>/dev/null || umount -l "$VIDNEST" 2>/dev/null || true
}

install_hdd_video() {
  # Civ II builds civ2\video\councilN.avi. CD D: is one search; HDD-relative
  # from the exe dir (Z:\...\apps\civ2\civ2\video) is another. Wine FindFirstFile
  # on a directory of exFAT symlinks returns ERROR_INVALID_FUNCTION.
  [ -d "$VIDOV" ] && [ -f "$VIDOV/COUNCIL0.AVI" ] || return 0
  unmount_hdd_video
  mkdir -p "$VIDHDD" "$VIDNEST"
  if mount --bind "$VIDOV" "$VIDHDD" && mount --bind "$VIDOV" "$VIDNEST"; then
    echo "civ2-cd: HDD VIDEO bind $VIDHDD and $VIDNEST"
  else
    echo "civ2-cd: HDD VIDEO bind failed" >&2
  fi
}

register_vfw_codecs() {
  winebin="$WIN/bin/wine"
  [ -x "$winebin" ] || return 0
  export HOME="${HOME:-/root}"
  export DISPLAY="${DISPLAY:-:0}"
  export WINEPREFIX="$PREFIX"
  export WINEARCH=win32
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
  key='HKLM\Software\Microsoft\Windows NT\CurrentVersion\Drivers32'
  WINEDEBUG=-all "$winebin" reg add "$key" /v vidc.msvc /d msvidc32.dll /f >/dev/null
  WINEDEBUG=-all "$winebin" reg add "$key" /v vidc.MSVC /d msvidc32.dll /f >/dev/null
  WINEDEBUG=-all "$winebin" reg add "$key" /v vidc.cram /d msvidc32.dll /f >/dev/null
  WINEDEBUG=-all "$winebin" reg add "$key" /v vidc.mrle /d msrle32.dll /f >/dev/null
  echo "civ2-cd: Drivers32 vidc.msvc/cram/mrle registered"
}

unmount_video_overlay() {
  umount "$VIDMNT" 2>/dev/null || umount -l "$VIDMNT" 2>/dev/null || true
  umount "$VIDLOWER" 2>/dev/null || true
}

mount_video_overlay() {
  [ -d "$VIDOV" ] && [ -f "$VIDOV/COUNCIL0.AVI" ] && [ -d "$VIDMNT" ] || return 0
  unmount_video_overlay
  mkdir -p "$VIDLOWER" "$VIDWORK"
  if mount --bind "$VIDMNT" "$VIDLOWER" 2>/dev/null \
     && mount -t overlay overlay -o "lowerdir=$VIDLOWER,upperdir=$VIDOV,workdir=$VIDWORK" "$VIDMNT" 2>/dev/null; then
    echo "civ2-cd: VIDEO overlay (MSVC advisor/anarchy AVI over original ISO)"
    return 0
  fi
  unmount_video_overlay
  if mount --bind "$VIDOV" "$VIDMNT" 2>/dev/null; then
    echo "civ2-cd: VIDEO bind $VIDOV (advisor AVI only)"
    return 0
  fi
  echo "civ2-cd: VIDEO overlay failed" >&2
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
  echo "civ2-cd: D: -> $MNT (${loop:-no-loop})"
  mount_video_overlay
  install_hdd_video
  register_vfw_codecs
  mark_wine_cdrom
}

case "$CMD" in
  start)
    [ -f "$ISO" ] || { echo "missing Civ II data ISO: $ISO" >&2; exit 1; }
    mkdir -p "$MNT"
    if ! mounted; then
      mount -o loop,ro "$ISO" "$MNT"
    fi
    attach_wine_d
    ;;
  stop)
    rm -f "$PREFIX/dosdevices/d:" "$PREFIX/dosdevices/d::"
    unmount_video_overlay
    unmount_hdd_video
    if mounted; then
      umount "$MNT" || umount -l "$MNT" || true
    fi
    echo "civ2-cd: unmounted"
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
