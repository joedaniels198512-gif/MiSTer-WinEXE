#!/bin/sh
# End-user installer. Copies the public WinEXE layout onto a MiSTer/SuperStation SD.
#   ./install.sh [/media/fat]
set -e
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
exec "$HERE/scripts/ss1-winexe-install-layout.sh" "${1:-/media/fat}"
