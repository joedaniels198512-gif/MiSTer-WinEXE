#!/bin/sh
# Stamp installer-equivalent SimCity 2000 Win95 registry (SETUP.INS keys).
# Safe to re-run. Call with wineserver stopped so user.reg/system.reg
# are not overwritten. Does not change FPGA / Xorg / presenter / input.
# Does not use sc2kfix or WIN95/SETUP.EXE.
set -e
WIN="${WIN:-/media/fat/Windows}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
REG="$WIN/bin/ss1-winexe-sc2k.reg"

[ -f "$PREFIX/drive_c/SC2K/SIMCITY.EXE" ] || { echo "missing C:\\SC2K\\SIMCITY.EXE" >&2; exit 1; }
[ -f "$REG" ] || { echo "missing $REG" >&2; exit 1; }

python3 - "$PREFIX/user.reg" "$PREFIX/system.reg" << 'PY'
import os, sys, time

user_reg, system_reg = sys.argv[1], sys.argv[2]
now = int(time.time())
# FILETIME-ish comment Wine writes; not required for load.
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
    """Replace or append a Wine REGISTRY Version 2 key block."""
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
            break
        i += 1
    block = ["[%s] %d\n" % (key, now), "#time=%s\n" % ft]
    for k, v in values:
        if k == "@":
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

hkcu = [
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Localize", [("Language", '"USA"')]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Options", [
        ("Speed", "dword:00000001"),
        ("Sound", "dword:00000001"),
        ("Music", "dword:00000001"),
        ("AutoGoto", "dword:00000001"),
        ("AutoBudget", "dword:00000000"),
        ("Disasters", "dword:00000001"),
        ("AutoSave", "dword:00000000"),
    ]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Paths", [
        ("Home", '"C:\\\\SC2K"'),
        ("Graphics", '"C:\\\\SC2K\\\\Bitmaps"'),
        ("Music", '"C:\\\\SC2K\\\\Sounds"'),
        ("Data", '"C:\\\\SC2K\\\\Data"'),
        ("Goodies", '"C:\\\\SC2K"'),
        ("Cities", '"C:\\\\SC2K\\\\Cities"'),
        ("SaveGame", '"C:\\\\SC2K\\\\Cities"'),
        ("TileSets", '"C:\\\\SC2K\\\\ScurkArt"'),
        ("Scenarios", '"C:\\\\SC2K\\\\Scenario"'),
    ]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Registration", [
        ("Mayor Name", '"Mayor McSim"'),
        ("Company Name", '"Maxis, Inc."'),
    ]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\REGISTRATION", [
        ("Mayor Name", '"Mayor McSim"'),
        ("Company Name", '"Maxis, Inc."'),
    ]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Version", [
        ("SimCity 2000", "dword:00000100"),
        ("SCURK", "dword:00000100"),
    ]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Windows", [
        ("Display", '"8 1"'),
        ("Color Check", "dword:00000000"),
    ]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\SCURK", [
        ("CycleColors", "dword:00000001"),
        ("GridHeight", "dword:00000002"),
        ("GridWidth", "dword:00000002"),
        ("ShowClipRegion", "dword:00000000"),
        ("ShowDrawGrid", "dword:00000000"),
        ("SnapToGrid", "dword:00000000"),
        ("Sound", "dword:00000001"),
    ]),
]

hklm = [
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Localize", [("Language", '"USA"')]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Paths", [
        ("Home", '"C:\\\\SC2K"'),
        ("Graphics", '"C:\\\\SC2K\\\\Bitmaps"'),
        ("Music", '"C:\\\\SC2K\\\\Sounds"'),
        ("Data", '"C:\\\\SC2K\\\\Data"'),
        ("Goodies", '"C:\\\\SC2K"'),
        ("Cities", '"C:\\\\SC2K\\\\Cities"'),
        ("SaveGame", '"C:\\\\SC2K\\\\Cities"'),
        ("TileSets", '"C:\\\\SC2K\\\\ScurkArt"'),
        ("Scenarios", '"C:\\\\SC2K\\\\Scenario"'),
    ]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Registration", [
        ("Mayor Name", '"Mayor McSim"'),
        ("Company Name", '"Maxis, Inc."'),
    ]),
    ("Software\\\\Maxis\\\\SimCity 2000\\\\Version", [
        ("SimCity 2000", "dword:00000100"),
        ("SCURK", "dword:00000100"),
    ]),
    ("Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\App Paths\\\\SimCity.exe", [
        ("@", '"C:\\\\SC2K\\\\SIMCITY.EXE"'),
        ("Path", '"C:\\\\SC2K"'),
    ]),
]

ut = read(user_reg)
for key, vals in hkcu:
    ut = upsert_key(ut, key, vals)
write(user_reg, ut)

st = read(system_reg)
for key, vals in hklm:
    st = upsert_key(st, key, vals)
write(system_reg, st)
print("stamped Software\\Maxis\\SimCity 2000 into user.reg + system.reg")
PY
