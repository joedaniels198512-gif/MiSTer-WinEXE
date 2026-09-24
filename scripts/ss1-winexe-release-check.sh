#!/bin/sh
# Lightweight release sanity. No device, no Wine, no games.
#   ss1-winexe-release-check.sh [repo-root]
set -eu
ROOT=$(CDPATH= cd "${1:-$(dirname "$0")/..}" && pwd)
cd "$ROOT"
fail=0
say() { echo "$*"; }
bad() { echo "FAIL $*" >&2; fail=1; }

ver=$(tr -d ' \n' < VERSION)
[ "$ver" = "0.1.0-beta" ] || bad "VERSION is '$ver' (expected 0.1.0-beta)"

[ -f LICENSE ] && [ -f COPYING ] && [ -f THIRD_PARTY_NOTICES.md ] \
  || bad "license files missing"
[ -f README.md ] && [ -f docs/APPS.md ] && [ -f docs/KNOWN_ISSUES.md ] \
  || bad "docs missing"
grep -q 'WinEXE' README.md || bad "README must name WinEXE"
grep -q 'WinEXE_Test.rbf' README.md && bad "README still documents WinEXE_Test.rbf as current"
grep -q 'vscode-file:' README.md && bad "README contains vscode-file links"
grep -E '\(vscode-file:' README.md docs/*.md >/dev/null 2>&1 && bad "docs contain vscode-file links"
if [ ! -f "Scripts/WinEXE Installer.sh" ] && [ ! -f "scripts/WinEXE Installer.sh" ]; then
  bad "missing WinEXE Installer.sh"
fi
[ -f scripts/winexe-env.sh ] || bad "missing scripts/winexe-env.sh"
grep -q 'games/WinEXE/apps' README.md || bad "README must use games/WinEXE/apps"
grep -qE '_Computer/WinEXE' README.md || bad "README must document _Computer/WinEXE"

# Profiles: required keys
for ini in profiles/*.ini; do
  grep -q '^\[app\]' "$ini" || bad "$ini missing [app]"
  grep -q '^name=' "$ini" || bad "$ini missing name="
  grep -q '^exe=' "$ini" || bad "$ini missing exe="
  grep -q '^\[display\]' "$ini" || bad "$ini missing [display]"
done

# WEX → profile
for wex in wex/*.wex; do
  prof=$(awk -F= '/^profile=/{print $2}' "$wex" | tr -d ' \r')
  [ -n "$prof" ] || bad "$wex has no profile="
  [ -f "profiles/${prof}.ini" ] || bad "$wex points at missing profiles/${prof}.ini"
done

# Runtime list files exist; helpers referenced by shipping profiles exist
while IFS= read -r name || [ -n "$name" ]; do
  case "$name" in ''|\#*) continue ;; esac
  [ -f "scripts/$name" ] || bad "runtime list missing scripts/$name"
done < release/runtime-files.list

for helper in \
  ss1-winexe-cnc-cd.sh ss1-cnc-pal8.sh ss1-cnc-capslie.sh \
  ss1-winexe-civ2-cd.sh ss1-winexe-civ2-cdaudio.sh \
  ss1-winexe-sc2k-config.sh ss1-winexe-sc2k-toolbar.sh \
  ss1-winexe-winamp-config.sh ss1-winexe-freecell-deal.sh
do
  [ -f "scripts/$helper" ] || bad "profile helper missing $helper"
done

# FPGA public name
grep -q '"WinEXE;;"' fpga/WinEXE.sv || bad "CONF_STR is not WinEXE;;"

# Forbidden payloads in the git index (tracked files only)
if git ls-files | grep -qiE '\.(exe|dll|iso|bin|cue|img|rom|avi|wav|mp3|wma|sav)$'; then
  bad "tracked proprietary/media extension"
fi
git ls-files | grep -qE '^tmp/|^extract' && bad "tracked tmp/extract path"

# Shell syntax for public runtime + packager
for sh in scripts/ss1-winexe-launch.sh scripts/ss1-winexe-install-layout.sh \
  scripts/ss1-winexe-check-layout.sh scripts/ss1-winexe-package-release.sh \
  scripts/ss1-winexe-release-check.sh install.sh \
  "Scripts/WinEXE Installer.sh" scripts/wine scripts/wineserver \
  scripts/winexe-env.sh
do
  sh -n "$sh" || bad "syntax $sh"
done

# No leftover public product name
if git ls-files '*.md' | xargs grep -l 'current FPGA core.*WinEXE_Test' >/dev/null 2>&1; then
  bad "docs still treat WinEXE_Test as the current core"
fi

if [ "$fail" -ne 0 ]; then
  echo "RELEASE_CHECK_FAIL"
  exit 1
fi
echo "RELEASE_CHECK_OK version=$ver"
exit 0
