#!/bin/sh
# WMP-session-only CLSID override: CoCreate(CLSID_DSoundRender / CLSID_AudioRender)
# loads ss1waveout.ax instead of quartz DirectSound. Restored on stop-wine.
# Does not change Filter Mapper merits. Does not affect other apps once restored.
# Requires wineserver stopped when applying (wmp9.sh already stop-wine first).
#
#   ss1-winexe-wmp9-waveout-clsid.sh apply
#   ss1-winexe-wmp9-waveout-clsid.sh restore
set -e
WIN="${WIN:-/media/fat/Windows}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
SYSREG="$PREFIX/system.reg"
STAMP="/tmp/ss1-wmp-dsound-clsid.override"
MODE="${1:-apply}"

CLSID_DS="{79376820-AE81-11D0-9EDF-00A0C9223196}"
CLSID_AR="{E30629D1-27E5-11CE-875D-00608CB78066}"
AX="C:\\\\windows\\\\system32\\\\ss1waveout.ax"

if [ "$MODE" = restore ]; then
  [ -f "$STAMP" ] || { echo "no CLSID override stamp"; exit 0; }
  python3 - "$SYSREG" "$STAMP" << 'PY'
import os, sys, time
reg, stamp = sys.argv[1], sys.argv[2]
now = int(time.time())
ft = "1dd462f20000000"

def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except FileNotFoundError:
        return ""

def upsert_key(text, key, values):
    header = "[%s]" % key
    lines = text.splitlines(True) or ["WINE REGISTRY Version 2\n", "\n"]
    start = None
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
        existing, start, end = {}, None, None
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

saved = {}
for line in open(stamp, encoding="utf-8", errors="replace"):
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        saved[k] = v
text = read(reg)
for clsid in ("{79376820-AE81-11D0-9EDF-00A0C9223196}", "{E30629D1-27E5-11CE-875D-00608CB78066}"):
    key = "Software\\\\Classes\\\\CLSID\\\\%s\\\\InprocServer32" % clsid
    orig = saved.get(clsid, '"c:\\\\windows\\\\system32\\\\quartz.dll"')
    text = upsert_key(text, key, [("@", orig), ("ThreadingModel", '"Both"')])
open(reg, "w", encoding="utf-8").write(text)
print("restored DSound/AudioRender InprocServer32")
PY
  rm -f "$STAMP"
  echo "CLSID override restored"
  exit 0
fi

[ -f "$SYSREG" ] || { echo "missing $SYSREG — mount prefix" >&2; exit 1; }
python3 - "$SYSREG" "$STAMP" "$AX" << 'PY'
import os, sys, time
reg, stamp, ax = sys.argv[1], sys.argv[2], sys.argv[3]
now = int(time.time())
ft = "1dd462f20000000"
clsids = (
    "{79376820-AE81-11D0-9EDF-00A0C9223196}",
    "{E30629D1-27E5-11CE-875D-00608CB78066}",
)

def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except FileNotFoundError:
        return ""

def upsert_key(text, key, values):
    header = "[%s]" % key
    lines = text.splitlines(True) or ["WINE REGISTRY Version 2\n", "\n"]
    start = None
    i = 0
    existing = {}
    while i < len(lines):
        if lines[i].startswith(header + " ") or lines[i].rstrip("\r\n") == header:
            start = i
            i += 1
            while i < len(lines) and not lines[i].startswith("["):
                i += 1
            end = i
            for line in lines[start+1:end]:
                if "=" in line and not line.strip().startswith("#"):
                    k, v = line.split("=", 1)
                    existing[k.strip().strip('"')] = v.strip()
            break
        i += 1
    else:
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
    orig = existing.get("@", existing.get("", '"c:\\\\windows\\\\system32\\\\quartz.dll"'))
    if start is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        return "".join(lines) + "".join(block), orig
    return "".join(lines[:start]) + "".join(block) + "".join(lines[end:]), orig

text = read(reg)
saved = []
for clsid in clsids:
    key = "Software\\\\Classes\\\\CLSID\\\\%s\\\\InprocServer32" % clsid
    text, orig = upsert_key(text, key, [("@", '"%s"' % ax), ("ThreadingModel", '"Both"')])
    saved.append("%s=%s" % (clsid, orig))
open(reg, "w", encoding="utf-8").write(text)
open(stamp, "w", encoding="utf-8").write("\n".join(saved) + "\n")
print("applied SS1 WaveOut InprocServer32 for DSound+AudioRender")
print("stamp", stamp)
PY
echo "CLSID override applied (WMP session). Restore with $0 restore"
