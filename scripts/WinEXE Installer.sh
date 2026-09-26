#!/bin/sh
# MiSTer Scripts menu entry. No compile. No SSH required.
#
#   Scripts -> WinEXE Installer
#   or:  ./Scripts/WinEXE\ Installer.sh [/media/fat]
set -e
FAT="${1:-/media/fat}"
WINEXE_ROOT="${WINEXE_ROOT:-$FAT/games/WinEXE}"
OLDWIN="$FAT/Windows"

HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PAYLOAD=""
for cand in \
  "$HERE/.." \
  "$FAT" \
  "$FAT/WinEXE-v0.1.0-beta" \
  "$HERE/../WinEXE-v0.1.0-beta"
do
  if [ -f "$cand/games/WinEXE/bin/ss1-winexe-launch.sh" ] || \
     [ -f "$cand/_Computer/WinEXE.rbf" ] || \
     ls "$cand"/_Computer/WinEXE_*.rbf >/dev/null 2>&1; then
    PAYLOAD=$(CDPATH='' cd "$cand" && pwd)
    break
  fi
done

echo "===== WinEXE Installer ====="
echo "target=$FAT"
echo "runtime=$WINEXE_ROOT"
echo "payload=${PAYLOAD:-MISSING}"

fail() {
  echo "ERROR: $*" >&2
  echo "INSTALL FAILED"
  exit 1
}

[ -n "$PAYLOAD" ] || fail "could not find the WinEXE release files. Extract WinEXE-v0.1.0-beta.zip to the SD card root, then run this script again."

copy_file() {
  src=$1
  dest=$2
  [ -f "$src" ] || return 1
  mkdir -p "$(dirname "$dest")"
  [ "$src" -ef "$dest" ] && return 0
  cp -f "$src" "$dest"
}

copy_tree() {
  src=$1
  dest=$2
  [ -d "$src" ] || return 0
  mkdir -p "$dest"
  [ "$src" -ef "$dest" ] && return 0
  cp -a "$src/." "$dest/"
}

# Stop before ANY installation write if an old installation is present.
# Migration is intentionally a separate operation; do not merge apps/media or
# touch an old prefix, even when a new runtime also exists.
for old in "$OLDWIN/bin" "$OLDWIN/apps" "$OLDWIN"/wineprefix*; do
  if [ -e "$old" ] || [ -L "$old" ]; then
    fail "Previous WinEXE installation found at $OLDWIN. Automatic migration is not currently performed. The old installation is untouched; migration will be handled separately."
  fi
done

# The runtime contains absolute paths. FAT is an alternate SD mount for testing
# or staging, not a request to relocate the runtime layout.
[ "$WINEXE_ROOT" = "$FAT/games/WinEXE" ] || fail "runtime must be under games/WinEXE"
for tool in python3 mountpoint gdb pidof taskset setsid; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool missing: $tool"
done
# Installing over running binaries or a live Wine session is unsafe.
if command -v pidof >/dev/null 2>&1 && pidof wineserver explorer.exe Xorg >/dev/null 2>&1; then
  fail "Stop WinEXE (full shutdown / leave the core) before installing."
fi
VERIFY="$PAYLOAD/games/WinEXE/bin/ss1-winexe-verify-package.py"
[ -f "$VERIFY" ] || fail "package verifier missing"
python3 "$VERIFY" "$PAYLOAD" || fail "release payload is incomplete or damaged"

INI="$FAT/MiSTer.ini"
if [ -f "$INI" ]; then
  python3 - "$INI" << 'CHECK_INI'
import configparser, sys
cfg = configparser.ConfigParser(strict=False, interpolation=None)
# MiSTer allows global keys before the first section.
cfg.read_string("[global]\n" + open(sys.argv[1]).read())
for section in cfg.sections():
    if section.lower() in {"winexe", "winexe_test"}:
        if cfg.get(section, "main", fallback="").strip() != "MiSTer_WinEXE":
            sys.exit("Existing [WinEXE] main setting conflicts; left unchanged. Correct it explicitly before installing.")
CHECK_INI
fi

mkdir -p "$FAT/_Computer" "$FAT/Scripts" "$FAT/docs/WinEXE" \
  "$WINEXE_ROOT/bin" "$WINEXE_ROOT/apps/diag" \
  "$WINEXE_ROOT/profiles" "$WINEXE_ROOT/logs" "$WINEXE_ROOT/iso"

# Canonical dated RBF. Fall back to undated name if that is all the zip has.
RBF_SRC=""
for cand in "$PAYLOAD"/_Computer/WinEXE_*.rbf "$PAYLOAD/_Computer/WinEXE.rbf" "$PAYLOAD/WinEXE.rbf"; do
  if [ -f "$cand" ]; then
    RBF_SRC=$cand
    break
  fi
done
[ -n "$RBF_SRC" ] || fail "WinEXE RBF missing from the release package"
RBF_NAME=$(basename "$RBF_SRC")
copy_file "$RBF_SRC" "$FAT/_Computer/$RBF_NAME"

if [ -f "$PAYLOAD/MiSTer_WinEXE" ]; then
  copy_file "$PAYLOAD/MiSTer_WinEXE" "$FAT/MiSTer_WinEXE"
  chmod +x "$FAT/MiSTer_WinEXE" 2>/dev/null || true
fi

if [ -f "$PAYLOAD/Scripts/WinEXE Installer.sh" ]; then
  copy_file "$PAYLOAD/Scripts/WinEXE Installer.sh" "$FAT/Scripts/WinEXE Installer.sh"
  chmod +x "$FAT/Scripts/WinEXE Installer.sh" 2>/dev/null || true
fi

SRC_RT="$PAYLOAD/games/WinEXE"
[ -d "$SRC_RT" ] || SRC_RT="$PAYLOAD/Windows"

if [ -d "$SRC_RT/bin" ]; then
  copy_tree "$SRC_RT/bin" "$WINEXE_ROOT/bin"
fi
chmod +x "$WINEXE_ROOT"/bin/* 2>/dev/null || true

if [ -d "$SRC_RT/profiles" ]; then
  copy_tree "$SRC_RT/profiles" "$WINEXE_ROOT/profiles"
elif [ -d "$PAYLOAD/profiles" ]; then
  cp -f "$PAYLOAD"/profiles/*.ini "$WINEXE_ROOT/profiles/"
fi

# .wex stay at games/WinEXE/*.wex for the OSD picker
if [ -d "$SRC_RT" ]; then
  for wex in "$SRC_RT"/*.wex; do
    [ -f "$wex" ] || continue
    copy_file "$wex" "$WINEXE_ROOT/$(basename "$wex")"
  done
fi
if [ -f "$SRC_RT/apps/README.md" ]; then
  copy_file "$SRC_RT/apps/README.md" "$WINEXE_ROOT/apps/README.md"
fi

copy_tree "$SRC_RT/x11" "$WINEXE_ROOT/x11"
copy_tree "$SRC_RT/host-libs" "$WINEXE_ROOT/host-libs"
copy_tree "$SRC_RT/wine-installer" "$WINEXE_ROOT/wine-installer"
copy_tree "$SRC_RT/box86-ss1" "$WINEXE_ROOT/box86-ss1"
copy_tree "$SRC_RT/box86-extracted" "$WINEXE_ROOT/box86-extracted"
chmod +x "$WINEXE_ROOT/box86-ss1/box86" \
  "$WINEXE_ROOT/wine-installer/opt/wine-devel/bin/"* \
  "$WINEXE_ROOT/x11/bin/"* "$WINEXE_ROOT/x11/lib/xorg/Xorg"

if [ -f "$SRC_RT/x11/lib/xorg/modules/drivers/dummy_drv.so" ]; then
  :
elif [ -f "$PAYLOAD/dummy_drv.so" ]; then
  mkdir -p "$WINEXE_ROOT/x11/lib/xorg/modules/drivers"
  cp -f "$PAYLOAD/dummy_drv.so" "$WINEXE_ROOT/x11/lib/xorg/modules/drivers/"
fi

# Only project-built helpers are copied from apps; user applications are not
# release payloads and must never be merged or overwritten by this installer.
for helper in ss1-cnc-pal8.exe ss1-cnc-pal8.dll ss1-cnc-capslie.exe ss1-cnc-cdprobe.exe; do
  copy_file "$SRC_RT/apps/diag/$helper" "$WINEXE_ROOT/apps/diag/$helper"
done
copy_file "$SRC_RT/wineprefix-prebuilt.tar.xz" "$WINEXE_ROOT/wineprefix-prebuilt.tar.xz"
sh "$WINEXE_ROOT/bin/ss1-winexe-install-prefix.sh" "$WINEXE_ROOT" "$OLDWIN"
PREFIX_IMG="$WINEXE_ROOT/wineprefix-prebuilt.ext4"
PREFIX_MNT="$WINEXE_ROOT/wineprefix-prebuilt"

# Add only missing WinEXE sections; preserve all existing configuration.
python3 - "$FAT/MiSTer.ini" "$PAYLOAD/docs/WinEXE/WinEXE.ini" <<'WRITE_INI'
import configparser, os, pathlib, sys, tempfile
ini, fragment = map(pathlib.Path, sys.argv[1:])
cfg = configparser.ConfigParser(strict=False, interpolation=None)
cfg.read_string("[global]\n" + (ini.read_text() if ini.exists() else ""))
existing = {s.lower() for s in cfg.sections()}
add = configparser.ConfigParser(interpolation=None)
add.read(fragment)
missing = [s for s in add.sections() if s.lower() not in existing]
if missing:
    content = ini.read_text() if ini.exists() else ""
    content += ''.join("\n[" + section + "]\nmain=MiSTer_WinEXE\n" for section in missing)
    fd, pending = tempfile.mkstemp(prefix='.MiSTer.ini.', dir=ini.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            out.write(content)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(pending, ini.stat().st_mode & 0o777 if ini.exists() else 0o644)
        os.replace(pending, ini)
    finally:
        if os.path.exists(pending):
            os.unlink(pending)
    print("MiSTer.ini: added " + ", ".join(missing))
else:
    print("MiSTer.ini: existing WinEXE sections preserved")
WRITE_INI

# Docs under the normal MiSTer docs tree
if [ -d "$PAYLOAD/docs/WinEXE" ]; then
  copy_tree "$PAYLOAD/docs/WinEXE" "$FAT/docs/WinEXE"
else
  for doc in README.md LICENSE COPYING THIRD_PARTY_NOTICES.md; do
    [ -f "$PAYLOAD/$doc" ] && cp -f "$PAYLOAD/$doc" "$FAT/docs/WinEXE/"
  done
  [ -f "$PAYLOAD/docs/APPS.md" ] && cp -f "$PAYLOAD/docs/APPS.md" "$FAT/docs/WinEXE/"
  [ -f "$PAYLOAD/docs/KNOWN_ISSUES.md" ] && cp -f "$PAYLOAD/docs/KNOWN_ISSUES.md" "$FAT/docs/WinEXE/"
fi

need() {
  if [ ! -e "$1" ]; then
    echo "MISSING $1"
    return 1
  fi
  echo "OK $1"
  return 0
}

err=0
need "$FAT/_Computer/$RBF_NAME" || err=1
need "$WINEXE_ROOT/bin/ss1-winexe-launch.sh" || err=1
need "$WINEXE_ROOT/bin/winexe-env.sh" || err=1
need "$WINEXE_ROOT/bin/ss1-winexe-x11-present" || err=1
need "$WINEXE_ROOT/bin/ss1-winexe-xorg.sh" || err=1
need "$WINEXE_ROOT/profiles/notepad.ini" || err=1
need "$WINEXE_ROOT/Notepad.wex" || err=1
need "$WINEXE_ROOT/x11/lib/xorg/modules/drivers/dummy_drv.so" || err=1
need "$WINEXE_ROOT/wine-installer/opt/wine-devel/bin/wine" || err=1
need "$WINEXE_ROOT/host-libs" || err=1
if [ ! -f "$PREFIX_MNT/system.reg" ] || [ ! -f "$PREFIX_MNT/user.reg" ]; then
  echo "MISSING $PREFIX_MNT (Wine prefix)"
  err=1
else
  echo "OK wine prefix"
fi
if [ ! -x "$WINEXE_ROOT/box86-ss1/box86" ]; then
  echo "MISSING $WINEXE_ROOT/box86-ss1/box86"
  err=1
else
  need "$WINEXE_ROOT/box86-ss1/box86" || err=1
fi
if [ -f "$FAT/MiSTer_WinEXE" ]; then
  echo "OK $FAT/MiSTer_WinEXE"
else
  echo "MISSING $FAT/MiSTer_WinEXE"
  err=1
fi
need "$FAT/docs/WinEXE/README.md" || err=1
if [ -d "$FAT/Windows" ]; then
  echo "NOTICE: $FAT/Windows left in place (previous beta; not required by this Main)"
fi

if [ "$err" -ne 0 ]; then
  echo "INSTALL FAILED"
  exit 1
fi

echo "SUCCESS"
echo "Next: copy your legally obtained apps into $WINEXE_ROOT/apps/"
echo "Then: Computer menu -> WinEXE -> F12 -> Load Application..."
exit 0
