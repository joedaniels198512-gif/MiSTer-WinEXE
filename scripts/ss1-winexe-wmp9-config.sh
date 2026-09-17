#!/bin/sh
# Stamp WMP9 first-run / paths / native DLL overrides. Wineserver must be
# stopped so user.reg/system.reg are not overwritten. From genuine XP SP3
# wmp.inf — not winetricks. Does not install Gecko.
set -e
WIN="${WIN:-/media/fat/Windows}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
REG="$WIN/bin/ss1-winexe-wmp9.reg"
[ -f "$PREFIX/drive_c/Program Files/Windows Media Player/wmplayer.exe" ] || {
  echo "missing wmplayer.exe — run ss1-winexe-wmp9-install.sh first" >&2
  exit 1
}
[ -f "$REG" ] || { echo "missing $REG" >&2; exit 1; }

python3 - "$PREFIX/user.reg" "$PREFIX/system.reg" "$PREFIX/userdef.reg" << 'PY'
import os, sys, time
user_reg, system_reg = sys.argv[1], sys.argv[2]
userdef = sys.argv[3] if len(sys.argv) > 3 else ""
now = int(time.time())
ft = "1dd462f20000000"

def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except FileNotFoundError:
        return ""

def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)

def upsert_key(text, key, values):
    header = "[%s]" % key
    start = None
    lines = text.splitlines(True)
    if not lines:
        lines = ["WINE REGISTRY Version 2\n", "\n"]
    i = 0
    while i < len(lines):
        if lines[i].startswith(header + " ") or lines[i].rstrip("\r\n") == header:
            start = i
            i += 1
            while i < len(lines) and not lines[i].startswith("["):
                i += 1
            end = i
            existing = {}
            for line in lines[start+1:end]:
                if "=" in line and not line.strip().startswith("#"):
                    k, v = line.split("=", 1)
                    existing[k.strip().strip('"')] = v.strip()
            break
        i += 1
    else:
        existing = {}
        start = end = None
    merged = dict(existing)
    for k, v in values:
        merged[k] = v
    block = ["[%s] %d\n" % (key, now), "#time=%s\n" % ft]
    for k, v in merged.items():
        if k in ("", "@"):
            block.append("@=%s\n" % v)
        else:
            block.append("\"%s\"=%s\n" % (k, v))
    block.append("\n")
    if start is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        return "".join(lines) + "".join(block)
    return "".join(lines[:start]) + "".join(block) + "".join(lines[end:])

# HKCU first-run (INF PerUserStub + skip privacy/EULA wizard)
hkcu = [
    ("Software\\\\Microsoft\\\\MediaPlayer\\\\Preferences", [
        ("AcceptedEULA", "dword:00000001"),
        ("AcceptedPrivacyStatement", "dword:00000001"),
        ("FirstRun", "dword:00000000"),
        ("LaunchOnlineStore", "dword:00000000"),
        ("UpgradeCheckFrequency", "dword:00000000"),
        ("StretchToFit", "dword:00000001"),
    ]),
    ("Software\\\\Classes\\\\Software\\\\Microsoft\\\\MediaPlayer\\\\Preferences", [
        ("AcceptedPrivacyStatement", "dword:00000001"),
    ]),
    ("Software\\\\Wine\\\\DllOverrides", [
        ("wmp", '"native,builtin"'),
        ("wmpdxm", '"native,builtin"'),
        ("wmpasf", '"native,builtin"'),
        ("wmpshell", '"native,builtin"'),
        ("wmpui", '"native,builtin"'),
        ("wmpvis", '"native,builtin"'),
        ("wmpcore", '"native,builtin"'),
        ("wmpcd", '"native,builtin"'),
        ("l3codeca.acm", '"native,builtin"'),
        ("l3codecx.ax", '"native,builtin"'),
        ("mpvis", '"native,builtin"'),
        ("wmvcore", '"native,builtin"'),
        ("wmasf", '"native,builtin"'),
        ("wmidx", '"native,builtin"'),
        ("drmclien", '"native,builtin"'),
        ("mshtml", '"disabled"'),
        ("ieframe", '"disabled"'),
        ("shdocvw", '"disabled"'),
        ("winemenubuilder.exe", '"disabled"'),
    ]),
]
text = read(user_reg)
for key, vals in hkcu:
    text = upsert_key(text, key, vals)
write(user_reg, text)

hklm = [
    ("Software\\\\Microsoft\\\\MediaPlayer", [
        ("Installation Directory", '"C:\\\\Program Files\\\\Windows Media Player"'),
        ("Installation DirectoryLFN", '"C:\\\\Program Files\\\\Windows Media Player"'),
        ("SkinsDir", '"C:\\\\Program Files\\\\Windows Media Player\\\\Skins"'),
        ("VisualizationsDir", '"C:\\\\Program Files\\\\Windows Media Player\\\\Visualizations"'),
        ("IEInstall", '"no"'),
    ]),
    ("Software\\\\Microsoft\\\\MediaPlayer\\\\Preferences", [
        ("AcceptedEULA", "dword:00000001"),
    ]),
    ("Software\\\\Microsoft\\\\MediaPlayer\\\\PlayerUpgrade", [
        ("EnableAutoUpgrade", '"no"'),
    ]),
    ("Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\App Paths\\\\wmplayer.exe", [
        ("@", '"C:\\\\Program Files\\\\Windows Media Player\\\\wmplayer.exe"'),
        ("Path", '"C:\\\\Program Files\\\\Windows Media Player"'),
    ]),
    ("Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\Drivers32", [
        ("msacm.l3acm", '"l3codeca.acm"'),
    ]),
    ("Software\\\\Microsoft\\\\Multimedia\\\\WMPlayer", [
        ("Player.Path", '"C:\\\\Program Files\\\\Windows Media Player\\\\wmplayer.exe"'),
        ("Player.Name", '"wmplayer.exe"'),
        ("StandardVerb", '"play"'),
    ]),
]
text = read(system_reg)
for key, vals in hklm:
    text = upsert_key(text, key, vals)
write(system_reg, text)
print("wmp9 registry stamped user.reg + system.reg")
PY
