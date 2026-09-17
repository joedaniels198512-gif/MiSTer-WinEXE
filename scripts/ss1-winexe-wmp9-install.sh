#!/bin/sh
# Install genuine XP SP3 in-box Windows Media Player 9 (wmplayer 9.00.00.4503)
# from files staged at $WIN/apps/wmp9 (extracted from the clean XP ISO).
# Reproduces wmp.inf copy + RunOnce regsvr32. Does NOT overwrite Wine quartz.
# Native WMP/WMF DLLs are prefix-local only (never write through wine-installer
# symlinks). No winetricks, no Gecko, no FPGA/Xorg change.
set -e
WIN="${WIN:-/media/fat/Windows}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
SRC="${WMP9_SRC:-$WIN/apps/wmp9}"
LOG="${WMP9_LOG:-$WIN/logs/wmp9-install.log}"
SYS32="$PREFIX/drive_c/windows/system32"
PF="$PREFIX/drive_c/Program Files/Windows Media Player"
INFDIR="$PREFIX/drive_c/windows/inf"

"$WIN/bin/ss1-mount-prefix.sh"
[ -f "$SRC/wmplayer.exe" ] || { echo "missing $SRC/wmplayer.exe" >&2; exit 1; }
[ -f "$SRC/wmp.dll" ] || { echo "missing $SRC/wmp.dll" >&2; exit 1; }

mkdir -p "$(dirname "$LOG")" "$PF/Skins" "$PF/Visualizations" "$SYS32" "$INFDIR"
: > "$LOG"
log() { echo "$@" | tee -a "$LOG"; }

copy_one() {
  src=$1 dest=$2
  [ -f "$src" ] || { log "SKIP missing $(basename "$src")"; return 1; }
  mkdir -p "$(dirname "$dest")"
  # Prefix system32 builtins are symlinks into wine-installer. Never write
  # through those links; replace the link with a prefix-local file.
  rm -f "$dest"
  cp "$src" "$dest"
  log "FILE $dest $(wc -c < "$dest" | tr -d ' ') bytes"
}

log "===== WMP9 install $(date -u +%Y-%m-%dT%H:%M:%SZ) src=$SRC prefix=$PREFIX ====="

# Program Files\Windows Media Player  (wmp.inf V9Copy.Core / V9Copy.Core.XP)
for f in wmplayer.exe mpvis.dll wmpns.dll wmpband.dll wmpstub.exe wmploc.js; do
  copy_one "$SRC/$f" "$PF/$f" || true
done
for f in compact.wmz Revert.wmz; do
  copy_one "$SRC/$f" "$PF/Skins/$f" || true
done
for f in wmpaud1.wav wmpaud2.wav wmpaud3.wav wmpaud4.wav wmpaud5.wav \
         wmpaud6.wav wmpaud7.wav wmpaud8.wav wmpaud9.wav; do
  copy_one "$SRC/$f" "$PF/$f" || true
done

# system32 — WMP COM, WMF reader, MP3 codec. Keep Wine quartz/msdmo/qasf.
for f in wmp.dll wmpui.dll wmpvis.dll wmpdxm.dll wmpasf.dll wmpshell.dll \
         wmploc.dll wmp.ocx wmpcd.dll wmpcore.dll l3codeca.acm l3codecx.ax \
         wmvcore.dll wmasf.dll wmidx.dll drmclien.dll; do
  copy_one "$SRC/$f" "$SYS32/$f" || true
done

# inf dir: wmp.inf + unregmp2.exe (TXTSETUP dir 20 / DIRID 17)
copy_one "$SRC/wmp.inf" "$INFDIR/wmp.inf" || true
copy_one "$SRC/wmpocm.inf" "$INFDIR/wmpocm.inf" || true
copy_one "$SRC/skins.inf" "$INFDIR/skins.inf" || true
copy_one "$SRC/unregmp2.exe" "$INFDIR/unregmp2.exe" || true

if [ -x "$WIN/bin/ss1-winexe-wmp9-config.sh" ]; then
  "$WIN/bin/ss1-winexe-wmp9-config.sh" | tee -a "$LOG"
fi

# COM registration via existing Wine regsvr32 (wmp.inf RunOnce list).
export WINEPREFIX="$PREFIX"
export WINEARCH="${WINEARCH:-win32}"
export DISPLAY="${DISPLAY:-:0}"
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mshtml=d;ieframe=d;shdocvw=d"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
export WINEDEBUG="${WINEDEBUG:-+err}"
. "$WIN/bin/ss1-x11-env.sh"

regone() {
  winpath=$1
  log "REGSVR32 $winpath"
  if "$WIN/bin/wine" regsvr32 /s "$winpath" >>"$LOG" 2>&1; then
    log "REGSVR32_OK $winpath"
  else
    rc=$?
    log "REGSVR32_FAIL $winpath rc=$rc"
  fi
}

# Order from wmp.inf WMPDelay.Actions (skip WMDM / migrate).
regone 'C:\windows\system32\wmp.dll'
regone 'C:\windows\system32\wmpshell.dll'
regone 'C:\windows\system32\wmpasf.dll'
regone 'C:\windows\system32\wmpdxm.dll'
regone 'C:\Program Files\Windows Media Player\mpvis.dll'
regone 'C:\windows\system32\wmpvis.dll'
regone 'C:\windows\system32\wmp.ocx'
regone 'C:\windows\system32\l3codecx.ax'
regone 'C:\windows\system32\drmclien.dll'

log "===== install done ====="
log "NOT copied (kept Wine): quartz.dll msdmo.dll qasf.dll blackbox.dll drmstor.dll"
echo "log=$LOG"
