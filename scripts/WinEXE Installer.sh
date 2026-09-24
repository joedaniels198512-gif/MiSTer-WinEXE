#!/bin/sh
# MiSTer Scripts menu entry. No compile. No SSH required.
#
#   Scripts -> WinEXE Installer
#   or:  ./Scripts/WinEXE\ Installer.sh [/media/fat]
set -e
FAT="${1:-/media/fat}"
WINEXE_ROOT="${WINEXE_ROOT:-$FAT/games/WinEXE}"
OLDWIN="$FAT/Windows"

HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
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
    PAYLOAD=$(CDPATH= cd "$cand" && pwd)
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
  cp -f "$src" "$dest"
}

copy_tree() {
  src=$1
  dest=$2
  [ -d "$src" ] || return 0
  mkdir -p "$dest"
  cp -a "$src/." "$dest/"
}

copy_tree_if_missing() {
  src=$1
  dest=$2
  [ -d "$src" ] || return 0
  mkdir -p "$dest"
  # Do not overwrite existing user files.
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --ignore-existing "$src"/ "$dest"/
  else
    (CDPATH= cd "$src" && find . -type f) | while IFS= read -r rel; do
      rel=${rel#./}
      if [ ! -e "$dest/$rel" ]; then
        mkdir -p "$dest/$(dirname "$rel")"
        cp -f "$src/$rel" "$dest/$rel"
      fi
    done
  fi
}

mkdir -p \
  "$FAT/_Computer" \
  "$FAT/Scripts" \
  "$FAT/docs/WinEXE" \
  "$WINEXE_ROOT/bin" \
  "$WINEXE_ROOT/apps/xp-games" \
  "$WINEXE_ROOT/apps/civ2" \
  "$WINEXE_ROOT/apps/cnc" \
  "$WINEXE_ROOT/profiles/experimental" \
  "$WINEXE_ROOT/logs" \
  "$WINEXE_ROOT/iso"

# --- migrate an older /media/fat/Windows beta without deleting it ---
if [ -d "$OLDWIN/bin" ] || [ -d "$OLDWIN/apps" ] || [ -d "$OLDWIN/wineprefix-prebuilt" ]; then
  echo "NOTICE: previous WinEXE beta found at $OLDWIN"
  echo "  New runtime root is $WINEXE_ROOT"
  echo "  User application files are copied only if missing at the destination."
  echo "  The old $OLDWIN tree is left in place (not deleted)."
  if [ -d "$OLDWIN/apps" ]; then
    copy_tree_if_missing "$OLDWIN/apps" "$WINEXE_ROOT/apps"
    echo "  apps: merged into $WINEXE_ROOT/apps (existing files kept)"
  fi
  if [ -d "$OLDWIN/iso" ]; then
    copy_tree_if_missing "$OLDWIN/iso" "$WINEXE_ROOT/iso"
  fi
fi

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
  cp -f "$SRC_RT"/bin/* "$WINEXE_ROOT/bin/" 2>/dev/null || true
fi
chmod +x "$WINEXE_ROOT"/bin/* 2>/dev/null || true

if [ -d "$SRC_RT/profiles" ]; then
  cp -f "$SRC_RT"/profiles/*.ini "$WINEXE_ROOT/profiles/" 2>/dev/null || true
  mkdir -p "$WINEXE_ROOT/profiles/experimental"
  cp -f "$SRC_RT"/profiles/experimental/*.ini "$WINEXE_ROOT/profiles/experimental/" 2>/dev/null || true
elif [ -d "$PAYLOAD/profiles" ]; then
  cp -f "$PAYLOAD"/profiles/*.ini "$WINEXE_ROOT/profiles/"
fi

# .wex stay at games/WinEXE/*.wex for the OSD picker
if [ -d "$SRC_RT" ]; then
  cp -f "$SRC_RT"/*.wex "$WINEXE_ROOT/" 2>/dev/null || true
fi
if [ -f "$SRC_RT/apps/README.md" ]; then
  copy_file "$SRC_RT/apps/README.md" "$WINEXE_ROOT/apps/README.md"
fi

copy_tree "$SRC_RT/x11" "$WINEXE_ROOT/x11"
copy_tree "$SRC_RT/host-libs" "$WINEXE_ROOT/host-libs"
copy_tree "$SRC_RT/wine-installer" "$WINEXE_ROOT/wine-installer"
copy_tree "$SRC_RT/box86-ss1" "$WINEXE_ROOT/box86-ss1"
copy_tree "$SRC_RT/box86-extracted" "$WINEXE_ROOT/box86-extracted"

if [ -f "$SRC_RT/x11/lib/xorg/modules/drivers/dummy_drv.so" ]; then
  :
elif [ -f "$PAYLOAD/dummy_drv.so" ]; then
  mkdir -p "$WINEXE_ROOT/x11/lib/xorg/modules/drivers"
  cp -f "$PAYLOAD/dummy_drv.so" "$WINEXE_ROOT/x11/lib/xorg/modules/drivers/"
fi

# Wine prefix: unpack the clean tar, then retarget Wine builtin symlinks.
PREFIX_IMG="$WINEXE_ROOT/wineprefix-prebuilt.ext4"
PREFIX_MNT="$WINEXE_ROOT/wineprefix-prebuilt"
SRC_IMG="$SRC_RT/wineprefix-prebuilt.ext4"
SRC_TAR="$SRC_RT/wineprefix-prebuilt.tar.xz"
[ -f "$SRC_TAR" ] || SRC_TAR="$PAYLOAD/wineprefix-prebuilt.tar.xz"

rewrite_prefix_links() {
  root=$1
  [ -d "$root" ] || return 0
  find "$root" -type l 2>/dev/null | while IFS= read -r link; do
    tgt=$(readlink "$link" 2>/dev/null) || continue
    case "$tgt" in
      /media/fat/Windows/*)
        newt="/media/fat/games/WinEXE/${tgt#/media/fat/Windows/}"
        ln -sfn "$newt" "$link"
        ;;
    esac
  done
}

prepare_prefix() {
  if [ -d "$OLDWIN/wineprefix-prebuilt" ] && [ -f "$OLDWIN/wineprefix-prebuilt/system.reg" ]; then
    if [ ! -f "$PREFIX_MNT/system.reg" ]; then
      echo "prefix: reusing existing beta prefix (not overwritten)"
      copy_tree "$OLDWIN/wineprefix-prebuilt" "$PREFIX_MNT"
      rewrite_prefix_links "$PREFIX_MNT"
      return 0
    fi
  fi
  if [ -f "$SRC_IMG" ]; then
    cp -f "$SRC_IMG" "$PREFIX_IMG"
  fi
  if [ -f "$PREFIX_IMG" ] && command -v mkfs.ext4 >/dev/null 2>&1 && [ -f /proc/mounts ]; then
    mkdir -p "$PREFIX_MNT"
    if ! grep -q " $PREFIX_MNT " /proc/mounts 2>/dev/null; then
      mount -o loop,noatime "$PREFIX_IMG" "$PREFIX_MNT" 2>/dev/null || true
    fi
    if [ -f "$PREFIX_MNT/system.reg" ]; then
      rewrite_prefix_links "$PREFIX_MNT"
      echo "prefix: mounted $PREFIX_IMG"
      return 0
    fi
  fi
  if [ -f "$SRC_TAR" ]; then
    mkdir -p "$WINEXE_ROOT"
    tar -C "$WINEXE_ROOT" -xJf "$SRC_TAR"
    rewrite_prefix_links "$PREFIX_MNT"
    echo "prefix: extracted wineprefix-prebuilt.tar.xz"
    return 0
  fi
  if [ -d "$SRC_RT/wineprefix-prebuilt" ]; then
    copy_tree "$SRC_RT/wineprefix-prebuilt" "$PREFIX_MNT"
    rewrite_prefix_links "$PREFIX_MNT"
    echo "prefix: copied directory"
    return 0
  fi
  fail "clean Wine prefix missing from the release package"
}

prepare_prefix

# MiSTer.ini: add [WinEXE] only. Do not rewrite other sections.
INI="$FAT/MiSTer.ini"
FRAG="$PAYLOAD/docs/WinEXE/WinEXE.ini"
[ -f "$FRAG" ] || FRAG="$PAYLOAD/mister/WinEXE.ini"
[ -f "$FRAG" ] || FRAG="$PAYLOAD/WinEXE.ini"
if [ -f "$FRAG" ]; then
  if [ -f "$INI" ]; then
    if grep -q '^\[WinEXE\]' "$INI"; then
      echo "MiSTer.ini: [WinEXE] already present (left unchanged)"
    else
      printf '\n' >> "$INI"
      cat "$FRAG" >> "$INI"
      echo "MiSTer.ini: appended [WinEXE] main=MiSTer_WinEXE"
    fi
  else
    echo "MiSTer.ini: not found (fragment is in docs/WinEXE/WinEXE.ini)"
  fi
fi

# Docs under the normal MiSTer docs tree
if [ -d "$PAYLOAD/docs/WinEXE" ]; then
  cp -f "$PAYLOAD"/docs/WinEXE/* "$FAT/docs/WinEXE/" 2>/dev/null || true
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
if [ ! -f "$PREFIX_MNT/system.reg" ] && [ ! -f "$PREFIX_IMG" ]; then
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
