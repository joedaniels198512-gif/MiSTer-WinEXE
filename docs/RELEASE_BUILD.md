# Building and installing the release

Run **Release sanity and package** in GitHub Actions. It calls the existing
component workflows at the same repository revision, builds the existing C&C
helpers, and downloads artifacts from that run only. It uploads a release ZIP;
it does not publish a GitHub Release or deploy to a SuperStation.

Wine remains 7.1. Box86 remains the public generic ARMHF
`0.3.9+20260911.b05cb3a-1` package. Their external package URLs and SHA-256 values
are pinned in `release/runtime-packages.json`. ARM shared helpers are built
against Bullseye, matching the runtime's glibc generation. No parked WMP
runtime or multimedia sidecars are added.

Each component artifact contains a provenance JSON recording the repository
commit, relevant source-file hashes, output hashes, and workflow run/attempt.
The packager rejects missing, modified, source-mismatched, or mixed-run inputs.
Rerun **all jobs** if retrying a release run; partial reruns cannot mix attempts.
`docs/WinEXE/BUILD_PROVENANCE.json` and `PACKAGE_SHA256.json` are in the ZIP.
The latter covers the packaged files, not subsequent user data in the prefix.
These records establish provenance/integrity, not hardware verification.

The expected local input layout is `artifacts/release/<artifact-name>/`, as
created by Actions download-artifact. `ARTIFACT_DIR` may select another such
verified tree. Old `gha-latest`/lab directories are not release inputs.
Build recipes are in `.github/workflows/`; there is no compilation on SS1.
Production FPGA builds run only through GitHub Actions with Quartus 17.0.2,
never locally on the Mac through Rosetta/Docker. Retrieve and verify the CI
artifact before controlled deployment and the user's physical verification.

Local checks:

```sh
sh scripts/ss1-winexe-release-check.sh
python3 -B release/test_release.py
# Requires Linux, root, loop mounts and e2fsprogs; uses temporary files only:
sudo python3 -B release/test_prefix_linux.py
# With all verified component artifacts available:
sh scripts/ss1-winexe-package-release.sh
```

## Fresh installation

Extract the ZIP to the SD root and run **Scripts → WinEXE Installer** with
WinEXE shut down. Installation checks the complete payload and its checksums
before copying it. Same-file copies are skipped for an in-place SD extraction.
Only the project's four helper binaries are supplied under `apps/diag`;
Windows applications, games, discs, music and saves remain user-supplied.

A fresh install needs space for the runtime plus a **512 MiB** prefix image.
The installer allocates a new temporary file, formats it as ext4 with
older-kernel-compatible features, loop-mounts it, and extracts the clean prefix
inside that filesystem. It validates the prefix, syncs and unmounts it, renames
the completed image to `wineprefix-prebuilt.ext4`, then mounts it at
`wineprefix-prebuilt`. It never extracts prefix symlinks directly onto exFAT
and never formats an existing image. `WINEXE_PREFIX_MB` can explicitly select
another size (minimum 256 MiB). An interrupted install can leave a temporary
image if unmounting fails; resolve that mount before removing the file.
The 512 MiB default is a growth allowance: the available prepared prefix uses
about 67.7 MiB by a conservative block-rounded estimate. Before allocation,
the installer requires that estimate to fit within 75% of the image and
checks for the image size plus 16 MiB of free destination space. These checks
do not reserve space against concurrent writers; allocation failures still
abort and clean up the new file.

Catchable failures/signals unmount mounts created by the prefix helper and
remove its incomplete temporary image. Pre-existing mounts are left alone.
If unmount fails, the helper reports the backing file and retains it; reruns
refuse leftover `.wineprefix-new.*` files rather than accepting a partial
prefix. SIGKILL or power loss cannot run cleanup. Inspect mounts and retained
temporary images before recovery. A successful install deliberately leaves
the completed prefix mounted; interruption after completion can therefore
leave that valid final image mounted too. Loop mounts use Linux mount's
autoclear handling; detach is dependent on a successful unmount and no other
open users, not an unconditional guarantee.

The installer uses the existing per-core `main=MiSTer_WinEXE` configuration.
It preserves an existing matching section, rejects a conflicting setting,
and adds missing WinEXE sections (creating MiSTer.ini if absent). Stock
MiSTer is not replaced. Existing valid new-layout prefixes are preserved;
invalid images or nonempty incomplete prefix directories cause a failure
instead of extraction over user data. Shut down Wine before reinstalling.

## Old installations

If `/media/fat/Windows` contains a WinEXE `bin`, `apps`, or prefix directory/image,
the installer **stops before installation writes**. It reports that automatic
migration is not currently performed and will be handled separately. It does
not copy applications, media or prefixes; it does not mount, rewrite, convert,
or delete the old prefix. This applies even if a new-layout installation also
exists. Extracting the ZIP yourself precedes the installer and is outside this
no-write guarantee; preserve existing files before extracting an update.

## Verification limits

CI validates package contents, source/output provenance, and Linux ext4 prefix
creation/reinstallation. The target still needs its normal MiSTer Linux tools
(including Python 3, GDB, mount/loop support, e2fsprogs and audio facilities).
Do not infer visible HDMI/CRT output, working input, or audible playback from
package checks. Fresh SD installation, reboot/remount, OSD launches, input
recovery, C&C PAL8/CD operation, and Civ II music require the user's physical
SuperStation verification. Existing device-specific audio configuration is
not replaced or created by this installer.
