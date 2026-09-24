#!/bin/sh
# Advanced / SSH fallback. The normal path is:
#   Scripts -> WinEXE Installer
set -e
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
if [ -f "$HERE/Scripts/WinEXE Installer.sh" ]; then
  exec "$HERE/Scripts/WinEXE Installer.sh" "${1:-/media/fat}"
fi
if [ -f "$HERE/scripts/WinEXE Installer.sh" ]; then
  exec "$HERE/scripts/WinEXE Installer.sh" "${1:-/media/fat}"
fi
if [ -f "$HERE/../Scripts/WinEXE Installer.sh" ]; then
  exec "$HERE/../Scripts/WinEXE Installer.sh" "${1:-/media/fat}"
fi
echo "missing WinEXE Installer.sh" >&2
exit 1
