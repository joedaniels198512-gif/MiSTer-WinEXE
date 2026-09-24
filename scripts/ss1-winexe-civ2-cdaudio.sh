#!/bin/sh
# Civ II CD-audio helper. Original mixed-mode BIN/CUE stays untouched.
# PCM copies of tracks 02–12 live under apps/civ2/cdaudio/.
#
#   ss1-winexe-civ2-cdaudio.sh start|stop|status
set -e
WIN="${WIN:-/media/fat/games/WinEXE}"
DIR="${SS1_CIV2_CDAUDIO_DIR:-$WIN/apps/civ2/cdaudio}"
CMD="${1:-start}"

case "$CMD" in
  start)
    n=$(ls "$DIR"/track0[2-9].pcm "$DIR"/track1[0-2].pcm 2>/dev/null | wc -l | awk '{print $1}')
    if [ "${n:-0}" -lt 11 ]; then
      echo "civ2-cdaudio: missing PCM under $DIR (have ${n:-0}/11)" >&2
      exit 1
    fi
    echo "civ2-cdaudio: $n tracks in $DIR"
    ;;
  stop)
    if [ -f /tmp/ss1-civ2-cdaudio.pid ]; then
      kill "$(cat /tmp/ss1-civ2-cdaudio.pid)" 2>/dev/null || true
      rm -f /tmp/ss1-civ2-cdaudio.pid
    fi
    echo "civ2-cdaudio: stopped"
    ;;
  status)
    ls -l "$DIR"/track*.pcm 2>/dev/null || echo "no pcm"
    ;;
  *)
    echo "usage: $0 start|stop|status" >&2
    exit 1
    ;;
esac
