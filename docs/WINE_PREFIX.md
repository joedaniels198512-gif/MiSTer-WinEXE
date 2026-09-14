# Wine 7.1 prefix for SuperStation One

The SuperStation One has ~512 MB HPS RAM and an exFAT SD card. Running
`wineboot` on the device is too I/O- and memory-heavy. The prefix is
therefore prepared on GitHub Actions (native x86_64 Linux) and copied to
the SuperStation.

End users should only unzip a prepared package and run a launcher. They
should not need Docker, compilers, GitHub Actions, or `wineboot`.

## How the prefix is produced

Workflow: `.github/workflows/prepare-wine-prefix.yml`

Script: `scripts/prepare-wine-prefix.sh`

On `ubuntu-22.04` the job:

1. Enables i386 and installs `wine32:i386` only for shared libraries.
2. Downloads WineHQ **7.1** bullseye i386 debs (same version already on the SS1).
   Wine is extracted, not compiled.
3. Places Wine at `/media/fat/Windows/wine-installer/opt/wine-devel` so
   prefix symlinks and registry unix paths match the SuperStation layout.
4. Runs `wineboot --init` with `WINEARCH=win32`.
5. Checks `cmd.exe /c ver` and `cmd.exe /c echo HELLO FROM WINDOWS ON SUPERSTATION`
   on the builder (native x86, not Box86).
6. Uploads `wineprefix-prebuilt.tar.xz` as a GitHub Actions artifact.

Generated prefixes are **not** committed to git. Use the workflow artifact.

## Re-run

Actions → **Prepare Wine 7.1 win32 prefix** → Run workflow.

Or push a change to the workflow/script.

## Deploy to SuperStation One

```text
WINEPREFIX=/media/fat/Windows/wineprefix-prebuilt
Box86=/media/fat/Windows/box86-ss1/box86
Wine=/media/fat/Windows/wine-installer/opt/wine-devel/bin/wine
```

Do not overwrite `box86-ss1` or an existing on-device prefix. Extract the
artifact to `wineprefix-prebuilt` (new directory).
