#!/bin/sh
# Source this later when a Wine GUI launcher is added.
# Do not source from ss1-cmd.sh — console Wine must keep DISPLAY unset.
#
#   . /media/fat/Windows/bin/ss1-x11-env.sh
X11="${X11_ROOT:-/media/fat/Windows/x11}"
HOSTLIBS="${HOSTLIBS:-/media/fat/Windows/host-libs}"
export DISPLAY="${DISPLAY:-:0}"
export LD_LIBRARY_PATH="$X11/lib${HOSTLIBS:+:$HOSTLIBS/lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$X11/bin:$PATH"
export XKB_CONFIG_ROOT="$X11/share/X11/xkb"
unset WAYLAND_DISPLAY
