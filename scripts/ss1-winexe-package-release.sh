#!/bin/sh
# Assemble a complete SD-root release from verified component artifacts.
set -eu
ROOT=$(CDPATH='' cd "${1:-$(dirname "$0")/..}" && pwd)
VER=$(tr -d ' \n' < "$ROOT/VERSION")
OUT=${2:-$ROOT/dist/WinEXE-v${VER}.zip}
ART=${ARTIFACT_DIR:-$ROOT/artifacts/release}
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/winexe-package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$(dirname "$OUT")"
OUT=$(CDPATH='' cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")
WIN="$STAGE/games/WinEXE"
DOC="$STAGE/docs/WinEXE"
mkdir -p "$WIN/bin" "$WIN/profiles" "$WIN/apps/diag" "$WIN/logs" "$WIN/iso" "$DOC" "$STAGE/Scripts" "$STAGE/_Computer"

# Fail before writing a release if any producer output is missing, modified,
# stale, or from another workflow run. No fallback to lab/"latest" binaries.
python3 "$ROOT/release/artifacts.py" verify "$ART" > "$DOC/BUILD_PROVENANCE.json"
cp "$ROOT/release/runtime-packages.json" "$DOC/runtime-packages.json"
for doc in README.md LICENSE COPYING THIRD_PARTY_NOTICES.md; do cp "$ROOT/$doc" "$DOC/"; done
for doc in APPS.md KNOWN_ISSUES.md RELEASE_BUILD.md; do cp "$ROOT/docs/$doc" "$DOC/"; done
cp "$ROOT/mister/WinEXE.ini" "$DOC/WinEXE.ini"
cp "$ROOT/release/runtime-files.list" "$DOC/runtime-files.list"
cp "$ROOT/release/package-files.list" "$DOC/package-files.list"
cp "$ROOT/scripts/WinEXE Installer.sh" "$STAGE/Scripts/"
cp "$ROOT"/profiles/*.ini "$WIN/profiles/"
# Experimental profiles are not usable without the parked runtime and are not
# release dependencies. Keep the pre-existing parked profile unchanged.
mkdir -p "$WIN/profiles/experimental"
cp "$ROOT"/profiles/experimental/*.ini "$WIN/profiles/experimental/"
cp "$ROOT"/wex/*.wex "$WIN/"
cp "$ROOT/apps/README.md" "$WIN/apps/"
while IFS= read -r name || [ -n "$name" ]; do
  case "$name" in ''|\#*) continue ;; esac
  cp "$ROOT/scripts/$name" "$WIN/bin/"
done < "$ROOT/release/runtime-files.list"

# A deterministic date works on BSD and GNU hosts alike.
EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" show -s --format=%ct HEAD)}
RBF_DATE=$(python3 -c 'import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime("%Y%m%d"))' "$EPOCH")
cp "$ART/WinEXE.rbf/WinEXE.rbf" "$STAGE/_Computer/WinEXE_${RBF_DATE}.rbf"
cp "$ART/MiSTer_WinEXE/MiSTer_WinEXE" "$STAGE/"
for name in ss1-winexe-x11-present ss1-pal8-map.so ss1-civ2-cdaudio.so; do
  cp "$ART/$name/$name" "$WIN/bin/"
done
for name in ss1-cnc-pal8.dll ss1-cnc-pal8.exe ss1-cnc-capslie.exe ss1-cnc-cdprobe.exe; do
  cp "$ART/ss1-cnc-pal8-guest/$name" "$WIN/apps/diag/"
done
for archive in wineprefix-prebuilt/wine-runtime.tar.xz box86-runtime/box86-runtime.tar.xz x11-runtime/x11-runtime.tar.xz host-libs/host-libs.tar.xz; do
  tar -C "$WIN" -xJf "$ART/$archive"
done
cp "$ART/wineprefix-prebuilt/wineprefix-prebuilt.tar.xz" "$WIN/"
cp "$ART/dummy_drv.so/dummy_drv.so" "$WIN/x11/lib/xorg/modules/drivers/"
cp "$WIN/bin/xorg.winexe.conf" "$WIN/x11/etc/X11/"
# Fix packaging-time paths in the generated fontconfig bundle only.
python3 - "$WIN/host-libs/etc/fonts/fonts.conf" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace('/media/fat/Windows/', '/media/fat/games/WinEXE/'))
PY
# ZIP extraction to exFAT must not depend on symlink support. Materialize
# runtime bundle links; the prefix's links remain inside its tar/ext4 image.
python3 - "$WIN" <<'PY'
from pathlib import Path
import shutil, sys
root = Path(sys.argv[1]).resolve()
for link in list(root.rglob('*')):
    if not link.is_symlink():
        continue
    target = link.resolve(strict=True)
    if root not in target.parents or not target.is_file():
        sys.exit('unsupported runtime symlink: ' + str(link))
    data = target.read_bytes()
    mode = target.stat().st_mode & 0o777
    link.unlink()
    link.write_bytes(data)
    link.chmod(mode)
PY
chmod +x "$STAGE/MiSTer_WinEXE" "$STAGE/Scripts/WinEXE Installer.sh" "$WIN"/bin/* \
  "$WIN/box86-ss1/box86" "$WIN/wine-installer/opt/wine-devel/bin/"* "$WIN/x11/bin/"* "$WIN/x11/lib/xorg/Xorg"
python3 "$ROOT/scripts/ss1-winexe-verify-package.py" "$STAGE" --write-manifest
# Write alongside the destination, then rename only on success. Do not destroy
# a previous archive when a missing input or zip error aborts packaging.
ZIP_TMP=$(mktemp -d "$(dirname "$OUT")/.winexe-zip.XXXXXX")
trap 'rm -rf "$STAGE" "$ZIP_TMP"' EXIT
(cd "$STAGE" && COPYFILE_DISABLE=1 zip -Xqr "$ZIP_TMP/release.zip" .)
unzip -tq "$ZIP_TMP/release.zip"
mv "$ZIP_TMP/release.zip" "$OUT"
echo "WROTE $OUT"
