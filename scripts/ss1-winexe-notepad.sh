#!/bin/sh
# WinEXE_Test GUI path via the generic profile launcher.
# Load core if needed, dummy Xorg, presenter, XP Notepad.
set -e
WIN="${WIN:-/media/fat/Windows}"
LAUNCH="$WIN/bin/ss1-winexe-launch.sh"
[ -x "$LAUNCH" ] || LAUNCH="$(dirname "$0")/ss1-winexe-launch.sh"
exec "$LAUNCH" launch notepad "$@"
