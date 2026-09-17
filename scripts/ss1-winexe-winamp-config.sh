#!/bin/sh
# Stamp persistent Winamp 2.91 first-run + mini-browser settings.
# Safe to re-run. Call with wineserver stopped so user.reg is not overwritten.
# Does not change FPGA / Xorg / presenter / input.
set -e
WIN="${WIN:-/media/fat/Windows}"
PREFIX="${WINEPREFIX:-$WIN/wineprefix-prebuilt}"
WA="$PREFIX/drive_c/Program Files/Winamp"
WINDDIR="$PREFIX/drive_c/windows"

[ -f "$WA/winamp.exe" ] || { echo "missing $WA/winamp.exe" >&2; exit 1; }

python3 - "$WA" "$WINDDIR" "$PREFIX/user.reg" << 'PY'
import os, re, sys, time

wa_dir, windir, user_reg = sys.argv[1], sys.argv[2], sys.argv[3]

def read_text(path):
    try:
        raw = open(path, "rb").read()
    except FileNotFoundError:
        return ""
    if raw.startswith(b"\xff\xfe"):
        return raw.decode("utf-16le")
    return raw.decode("utf-8", "replace")

def write_crlf(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = text.replace("\r\n", "\n").replace("\n", "\r\n")
    if not data.endswith("\r\n"):
        data += "\r\n"
    open(path, "wb").write(data.encode("utf-8"))

def upsert_ini(path, section, keys):
    text = read_text(path).replace("\r\n", "\n")
    if not text.endswith("\n") and text:
        text += "\n"
    sec_re = re.compile(r"^\[%s\]\s*$" % re.escape(section), re.I | re.M)
    m = sec_re.search(text)
    if not m:
        block = "[%s]\n" % section + "".join("%s=%s\n" % kv for kv in keys.items())
        text = (text + ("\n" if text and not text.endswith("\n") else "") + block)
        write_crlf(path, text)
        return
    start = m.end()
    nxt = re.search(r"^\[", text[start:], re.M)
    end = start + nxt.start() if nxt else len(text)
    body = text[start:end]
    for k, v in keys.items():
        pat = re.compile(r"^%s=.*$" % re.escape(k), re.I | re.M)
        if pat.search(body):
            body = pat.sub("%s=%s" % (k, v), body, count=1)
        else:
            if body and not body.endswith("\n"):
                body += "\n"
            body += "%s=%s\n" % (k, v)
    if body and not body.startswith("\n"):
        body = "\n" + body
    if body and not body.endswith("\n"):
        body += "\n"
    text = text[:start] + body + text[end:]
    write_crlf(path, text)

# First-run / "Winamp Setup: User information" is NOT noaod in Program Files.
# winamp.exe (2.91) reads [WinampReg] NeedReg from GetWindowsDirectory()\\winamp.ini
# (C:\\windows\\winamp.ini). Missing key defaults to show-the-dialog; NeedReg=0 skips it.
# ID is the existing install id written by Winamp; keep it if present.
wind_ini = os.path.join(windir, "winamp.ini")
existing_id = "8048308F12BE0E40A753497BDAA12E8D"
m = re.search(r"^ID=(.*)$", read_text(wind_ini).replace("\r\n", "\n"), re.I | re.M)
if m and m.group(1).strip():
    existing_id = m.group(1).strip()
write_crlf(wind_ini, "[WinampReg]\nNeedReg=0\nID=%s\n" % existing_id)

# Mini-browser + version/stats nag live in Program Files\\Winamp\\Winamp.ini.
# mb_open=0 keeps the HTML minibrowser closed so Wine never loads ieframe/mshtml.
wa_ini = os.path.join(wa_dir, "Winamp.ini")
upsert_ini(wa_ini, "Winamp", {
    "noaod": "1",
    "newverchk": "0",
    "newverchk2": "0",
    "mb_open": "0",
    "splash": "0",
    "check_ft_startup": "0",
    "outname": "out_wave.dll",
    "mw_open": "1",
    "eq_open": "1",
    "pe_open": "1",
    "visplugin_autoexec": "0",
})

# Persistent Wine AppDefaults so gecko is not requested even if HTML is touched.
reg = read_text(user_reg)
section = "[Software\\\\Wine\\\\AppDefaults\\\\winamp.exe\\\\DllOverrides]"
if section not in reg:
    ts = int(time.time())
    block = (
        "\n%s %d\n"
        "#time=1dd4629cc000000\n"
        "\"mshtml\"=\"disabled\"\n"
        "\"ieframe\"=\"disabled\"\n"
        "\"shdocvw\"=\"disabled\"\n"
    ) % (section, ts)
    if not reg.endswith("\n"):
        reg += "\n"
    open(user_reg, "a").write(block)
else:
    def force_disabled(text, name):
        pat = re.compile(r'^"%s"=".*"$' % name, re.I | re.M)
        line = '"%s"="disabled"' % name
        if pat.search(text):
            return pat.sub(line, text, count=1)
        # insert after the section header
        return re.sub(
            r"^(\[Software\\\\Wine\\\\AppDefaults\\\\winamp\.exe\\\\DllOverrides\][^\n]*\n(?:#time=.*\n)?)",
            r"\1" + line + "\n",
            text,
            count=1,
            flags=re.M,
        )
    for dll in ("mshtml", "ieframe", "shdocvw"):
        reg = force_disabled(reg, dll)
    open(user_reg, "w").write(reg)

print("NeedReg=0", wind_ini)
print("mb_open=0", wa_ini)
print("AppDefaults winamp.exe mshtml/ieframe/shdocvw=disabled")
PY
echo "winamp config stamped prefix=$PREFIX"
