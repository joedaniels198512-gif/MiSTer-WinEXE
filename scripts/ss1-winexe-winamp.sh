#!/bin/sh
# Launch genuine Winamp 2.91 on the WinEXE stack via profile.
# Optional MP3 path is appended as a Wine argument.
set -e
WIN="${WIN:-/media/fat/games/WinEXE}"
LAUNCH="$WIN/bin/ss1-winexe-launch.sh"
[ -x "$LAUNCH" ] || LAUNCH="$(dirname "$0")/ss1-winexe-launch.sh"
MP3=${1:-}
if [ -z "$MP3" ]; then
  if [ -f "$WIN/wineprefix-prebuilt/drive_c/WA.mp3" ]; then
    MP3="$WIN/wineprefix-prebuilt/drive_c/WA.mp3"
  elif [ -f "$WIN/music/08 In The End.mp3" ]; then
    MP3="$WIN/music/08 In The End.mp3"
  fi
fi
WINMP3=""
case "$MP3" in
  *.mp3|*.MP3)
    if [ -f "$MP3" ]; then
      case "$MP3" in
        "$WIN/wineprefix-prebuilt/drive_c"/*)
          rel=${MP3#"$WIN/wineprefix-prebuilt/drive_c/"}
          WINMP3="C:\\$(echo "$rel" | sed 's|/|\\|g')"
          ;;
        *)
          WINMP3="Z:\\$(echo "$MP3" | sed 's|/|\\|g')"
          ;;
      esac
    fi
    ;;
esac
if [ -n "$WINMP3" ]; then
  exec "$LAUNCH" launch winamp2 -- "$WINMP3"
fi
exec "$LAUNCH" launch winamp2
