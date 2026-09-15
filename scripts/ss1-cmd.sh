#!/bin/sh
# SuperStation One launcher for Wine console commands.
# Usage: ss1-cmd.sh /c ver
#        ss1-cmd.sh /c echo HELLO FROM WINDOWS ON SUPERSTATION
set -e

BOX86="${BOX86:-/media/fat/Windows/box86-ss1/box86}"
WINE="${WINE:-/media/fat/Windows/wine-installer/opt/wine-devel/bin/wine}"
WINESERVER_BIN="${WINESERVER_BIN:-/media/fat/Windows/wine-installer/opt/wine-devel/bin/wineserver}"
WINEPREFIX="${WINEPREFIX:-/media/fat/Windows/wineprefix-prebuilt}"

export WINEPREFIX
export WINEARCH=win32
export WINELOADER="${WINELOADER:-$WINE}"
export WINESERVER="${WINESERVER:-$WINESERVER_BIN}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
export WINEDEBUG="${WINEDEBUG:--all}"
export BOX86_NOBANNER="${BOX86_NOBANNER:-1}"
export BOX86_LD_LIBRARY_PATH="${BOX86_LD_LIBRARY_PATH:-/media/fat/Windows/box86-extracted/usr/lib/box86-i386-linux-gnu:/media/fat/Windows/wine-installer/opt/wine-devel/lib:/media/fat/Windows/wine-installer/opt/wine-devel/lib/wine/i386-unix}"
# Native ARM libs for Box86 wrappers (not x86). Do not use system /usr.
export LD_LIBRARY_PATH="/media/fat/Windows/host-libs/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-/media/fat/Windows/host-libs/etc/fonts/fonts.conf}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-/media/fat/Windows/host-libs/etc/fonts}"
unset DISPLAY
unset WAYLAND_DISPLAY

exec "$BOX86" "$WINE" cmd "$@"
