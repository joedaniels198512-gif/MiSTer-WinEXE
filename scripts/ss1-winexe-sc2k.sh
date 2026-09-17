#!/bin/sh
# Launch original Win95 SimCity 2000 via the generic profile.
# 30 Hz, dirty 32×32, CPU affinity, registry, toolbar watcher are in sc2k.ini.
set -e
WIN="${WIN:-/media/fat/Windows}"
LAUNCH="$WIN/bin/ss1-winexe-launch.sh"
[ -x "$LAUNCH" ] || LAUNCH="$(dirname "$0")/ss1-winexe-launch.sh"
exec "$LAUNCH" launch sc2k "$@"
