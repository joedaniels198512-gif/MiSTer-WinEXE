# ARMHF host libraries for SuperStation One

Box86 wraps native ARM libraries when Wine asks for them. The SuperStation
image does not ship `libfontconfig.so.1`. Installing it into `/usr` is not
allowed; the libraries ship in the prepared package.

## How the bundle is produced

Workflow: `.github/workflows/prepare-host-libs.yml`

Script: `scripts/prepare-host-libs.sh`

On `ubuntu-22.04` the job downloads **Debian Bullseye armhf** debs from a
pinned `snapshot.debian.org` timestamp (glibc 2.31 era) and extracts them.
Nothing is compiled.

Contents go under `/media/fat/Windows/host-libs/`:

| Path | Role |
|---|---|
| `lib/libfontconfig.so.1` | Missing Wine/Box86 native lib |
| `lib/libexpat.so.1` and other NEEDED ARMHF deps | Relocatable runtime |
| `etc/fonts/fonts.conf` | Relocatable fontconfig config |
| `bin/fc-list` | Optional on-device init check |

## Runtime environment on the SuperStation

```sh
export LD_LIBRARY_PATH=/media/fat/Windows/host-libs/lib
export FONTCONFIG_FILE=/media/fat/Windows/host-libs/etc/fonts/fonts.conf
export FONTCONFIG_PATH=/media/fat/Windows/host-libs/etc/fonts
```

Do not install these into `/usr` or `/lib`. Do not add them to the system
`ldconfig` cache.
