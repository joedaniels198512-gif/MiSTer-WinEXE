#!/bin/sh
# Launch Wine builtin notepad.exe on SuperStation One.
# Mounts the ext4 prefix, starts Xorg+fbdev+evdev, presents /dev/fb0 onto
# the Menu wallpaper plane, then runs one Wine process.
set -e
WIN=/media/fat/Windows
. "$WIN/bin/ss1-x11-env.sh"
"$WIN/bin/ss1-mount-prefix.sh"
export WINEPREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"

# Persistent launch: setsid + logs under /media/fat/Windows/logs/.
# Does not attach Wine to this SSH TTY (Ctrl-C will not kill Notepad).
exec "$WIN/bin/ss1-launch-notepad.sh"
