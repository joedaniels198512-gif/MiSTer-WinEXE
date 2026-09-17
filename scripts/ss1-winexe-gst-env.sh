#!/bin/sh
# Private ARMHF GStreamer 1.18 (Debian bullseye) for WinEXE winegstreamer.
# Source from the WMP launcher only — do not source globally / from Winamp.
#   . /media/fat/Windows/bin/ss1-winexe-gst-env.sh
GST_ROOT="${GST_ROOT:-/media/fat/Windows/runtime/gstreamer}"
export LD_LIBRARY_PATH="$GST_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GST_PLUGIN_PATH="$GST_ROOT/lib/gstreamer-1.0"
export GST_PLUGIN_SYSTEM_PATH="$GST_ROOT/lib/gstreamer-1.0"
export GST_PLUGIN_SCANNER="$GST_ROOT/libexec/gst-plugin-scanner"
export GST_REGISTRY="${GST_REGISTRY:-/tmp/ss1-gst-registry.bin}"
export GST_REGISTRY_1_0="$GST_REGISTRY"
# Keep plugin-scanner from walking the system tree.
export GST_PLUGIN_SYSTEM_PATH_1_0="$GST_PLUGIN_SYSTEM_PATH"
# Box86+Wine: forking the ARM plugin-scanner from the i386 process
# segfaults ("Caught a segmentation fault while loading plugin file: (null)").
# Use a prebuilt registry and do not rescan/fork.
export GST_REGISTRY_FORK=no
export GST_REGISTRY_UPDATE=no
