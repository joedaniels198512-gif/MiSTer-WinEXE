#!/bin/bash
# Package the existing public Box86 binary, never a floating/latest build.
set -euo pipefail
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
python3 - "$ROOT/release/runtime-packages.json" "$WORK/box86.deb" <<'PY'
import hashlib, json, sys, urllib.request
spec = json.load(open(sys.argv[1]))['box86']
with urllib.request.urlopen(spec['url']) as response:
    data = response.read()
if hashlib.sha256(data).hexdigest() != spec['sha256']:
    sys.exit('Box86 checksum mismatch')
open(sys.argv[2], 'wb').write(data)
PY
mkdir -p "$WORK/extract"
# Newer .deb packages use zstd; Bullseye dpkg cannot read their control archive.
# Only the checksum-verified data archive is needed here.
member=$(ar t "$WORK/box86.deb" | sed -n '/^data\.tar\./p')
case "$member" in
  data.tar.zst) ar p "$WORK/box86.deb" "$member" | tar --zstd -x -C "$WORK/extract" ;;
  data.tar.xz) ar p "$WORK/box86.deb" "$member" | tar -xJ -C "$WORK/extract" ;;
  data.tar.gz) ar p "$WORK/box86.deb" "$member" | tar -xz -C "$WORK/extract" ;;
  *) echo "Unsupported Box86 data archive: $member" >&2; exit 1 ;;
esac
mkdir -p "$WORK/runtime/box86-ss1" "$WORK/runtime/box86-extracted/usr/lib"
cp "$WORK/extract/usr/local/bin/box86" "$WORK/runtime/box86-ss1/box86"
cp -a "$WORK/extract/usr/lib/box86-i386-linux-gnu" "$WORK/runtime/box86-extracted/usr/lib/"
cp "$WORK/extract/usr/share/doc/box86-generic-arm/LICENSE" "$WORK/runtime/box86-ss1/"
cp "$WORK/extract/etc/box86.box86rc" "$WORK/runtime/box86-ss1/"
python3 - "$ROOT/release/runtime-packages.json" > "$WORK/runtime/box86-ss1/SOURCE.txt" <<'PY'
import json, sys
print(json.dumps(json.load(open(sys.argv[1]))['box86'], indent=2))
PY
tar -C "$WORK/runtime" -cJf box86-runtime.tar.xz box86-ss1 box86-extracted
