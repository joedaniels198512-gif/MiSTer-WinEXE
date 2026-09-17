# WinEXE `.WEX` launchers

Selectable items for the MiSTer file browser (`F0,WEX,Load Application...`).
Each file is a pointer at an existing `profiles/*.ini`. Settings live in the
INI; do not duplicate them here.

Installed on the SuperStation as `/media/fat/games/WinEXE/`, which is the
stock `HomeDir()` for a core named `WinEXE`. The file browser opens there
without a custom start-path hack.

`/media/fat/Windows/Apps` was considered, but the SD card is exFAT and
already has `Windows/apps` (PE32 drops). Those names collide.

Do not put copyrighted EXEs in this directory.
