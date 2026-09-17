#!/bin/sh
# WMP-session Wine loader: Box86 gstflow only. Does not replace
# /media/fat/Windows/bin/wine (original Box86).
export WINEPREFIX="${WINEPREFIX:-/media/fat/Windows/wineprefix-prebuilt}"
export WINEARCH="${WINEARCH:-win32}"
export WINELOADER="${WINELOADER:-/media/fat/Windows/bin/wine-gstflow}"
export WINESERVER="${WINESERVER:-/media/fat/Windows/bin/wineserver}"
export BOX86_LD_LIBRARY_PATH="/media/fat/Windows/box86-extracted/usr/lib/box86-i386-linux-gnu:/media/fat/Windows/wine-installer/opt/wine-devel/lib:/media/fat/Windows/wine-installer/opt/wine-devel/lib/wine/i386-unix${BOX86_LD_LIBRARY_PATH:+:$BOX86_LD_LIBRARY_PATH}"
export BOX86_NOBANNER="${BOX86_NOBANNER:-1}"
export LD_LIBRARY_PATH="/media/fat/Windows/runtime/gstreamer/lib:/media/fat/Windows/x11/lib:/media/fat/Windows/host-libs/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-/media/fat/Windows/host-libs/etc/fonts/fonts.conf}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-/media/fat/Windows/host-libs/etc/fonts}"
exec /media/fat/Windows/box86-ss1/box86-gstflow /media/fat/Windows/wine-installer/opt/wine-devel/bin/wine "$@"
