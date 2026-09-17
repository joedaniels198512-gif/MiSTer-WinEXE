# Drop Windows applications here

Copy genuine 32-bit (PE32 / i386) files onto the SuperStation. **Do not
commit them** — they are copyrighted.

```
/media/fat/Windows/apps/notepad.exe      # XP SP3 Notepad (proven)
/media/fat/Windows/apps/mspaint.exe      # XP SP3 Paint (proven)
/media/fat/Windows/apps/MFC42u.dll       # sidecar from the same ISO if Paint needs it
```

Winamp 2.91 installs into the prefix:

```
C:\Program Files\Winamp\winamp.exe
```

SimCity 2000 Special Edition (Win95 tree, not DOS):

```
C:\SC2K\          # entire WIN95/SC2K/ folder, not only SIMCITY.EXE
```

Saves belong under `C:\SC2K\Cities\`, not Program Files.

## Launch

```sh
/media/fat/Windows/bin/ss1-winexe-notepad.sh
/media/fat/Windows/bin/ss1-winexe-run-exe.sh mspaint.exe
/media/fat/Windows/bin/ss1-winexe-winamp.sh
/media/fat/Windows/bin/ss1-winexe-sc2k.sh
```

`ss1-run-exe.sh` is the older parked `/dev/fb0` helper. Use the
`ss1-winexe-*` launchers on `WinEXE_Test`.

Do not put 64-bit (PE32+) binaries here. Box86 + Wine 7.1 i386 will
refuse them.
