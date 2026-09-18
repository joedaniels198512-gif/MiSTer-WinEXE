# Drop Windows applications here

Copy genuine 32-bit (PE32 / i386) files onto the SuperStation.
**Do not commit them.** They are copyrighted.

Full per-app table: [docs/APPS.md](../docs/APPS.md).

```
/media/fat/Windows/apps/notepad.exe
/media/fat/Windows/apps/mspaint.exe
/media/fat/Windows/apps/MFC42u.dll
/media/fat/Windows/apps/xp-games/     # winmine.exe sol.exe freecell.exe mshearts.exe cards.dll
/media/fat/Windows/apps/cnc/          # C&C95.EXE + HDD data
/media/fat/Windows/apps/civ2/         # civ2.exe + HDD data
```

Winamp 2.91 and SimCity 2000 live in the Wine prefix (`C:\Program Files\Winamp`,
`C:\SC2K\`). Disc images stay under `/media/fat/Windows/iso/` on the
device only.

OSD: load **WinEXE**, then **Load Application...**.
SSH: `/media/fat/Windows/bin/ss1-winexe-launch.sh launch notepad`

Do not put PE32+ (64-bit) binaries here.
