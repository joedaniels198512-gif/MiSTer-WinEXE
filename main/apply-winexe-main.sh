#!/bin/sh
# Apply the WinEXE hook to a Main_MiSTer source tree.
# Usage: apply-winexe-main.sh /path/to/Main_MiSTer
set -e
MAIN=${1:?Main_MiSTer source directory}
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)

test -f "$MAIN/user_io.cpp"
test -f "$MAIN/user_io.h"
test -f "$MAIN/support.h"

mkdir -p "$MAIN/support/winexe"
cp -f "$HERE/support/winexe/winexe.cpp" "$MAIN/support/winexe/winexe.cpp"
cp -f "$HERE/support/winexe/winexe.h" "$MAIN/support/winexe/winexe.h"

python3 - "$MAIN" << 'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])

def must(cond, msg):
    if not cond:
        raise SystemExit(msg)

user_io_h = root / "user_io.h"
h = user_io_h.read_text(encoding="utf-8", errors="replace")
if "char is_winexe();" not in h:
    h2, n = re.subn(r"(char is_x86\(\);\n)", r"\1char is_winexe();\n", h, count=1)
    must(n == 1, "user_io.h: is_x86 declaration not found")
    user_io_h.write_text(h2, encoding="utf-8")
    print("patched user_io.h is_winexe")
else:
    print("already patched user_io.h")

cpp_path = root / "user_io.cpp"
cpp = cpp_path.read_text(encoding="utf-8", errors="replace")

if "support/winexe/winexe.h" not in cpp:
    cpp2, n = re.subn(r'(#include "support.h"\n)', r'\1#include "support/winexe/winexe.h"\n', cpp, count=1)
    must(n == 1, "user_io.cpp: support.h include not found")
    cpp = cpp2
    print("patched user_io.cpp include")

if "char is_winexe()" not in cpp:
    fn = (
        "static int is_winexe_type = 0;\n"
        "char is_winexe()\n"
        "{\n"
        "\tif (!is_winexe_type)\n"
        "\t{\n"
        "\t\tif (!strcasecmp(orig_name, \"WinEXE\") || !strcasecmp(orig_name, \"WinEXE_Test\"))\n"
        "\t\t\tis_winexe_type = 1;\n"
        "\t\telse\n"
        "\t\t\tis_winexe_type = 2;\n"
        "\t}\n"
        "\treturn (is_winexe_type == 1);\n"
        "}\n\n"
    )
    cpp2, n = re.subn(r"(static int is_snes_type = 0;\n)", fn + r"\1", cpp, count=1)
    must(n == 1, "user_io.cpp: is_snes_type not found")
    cpp = cpp2
    print("patched user_io.cpp is_winexe()")

if "winexe_init()" not in cpp:
    cpp2, n = re.subn(r"(\n[ \t]*parse_config\(\);\n)", r"\1\tif (is_winexe()) winexe_init();\n", cpp, count=1)
    must(n == 1, "user_io.cpp: parse_config() not found")
    cpp = cpp2
    print("patched user_io.cpp winexe_init")

if "winexe_status_event" not in cpp:
    m = re.search(
        r"spi_uio_cmd_cont\(UIO_SET_STATUS2\);.*?DisableIO\(\);\n[ \t]*\}\n\}",
        cpp,
        re.S,
    )
    must(m, "user_io.cpp: user_io_status_set tail not found")
    insert_at = m.end() - 1  # strip the function-closing '}'
    cpp = cpp[:insert_at] + "\tif (is_winexe() && value) winexe_status_event(opt, value);\n}"
    print("patched user_io.cpp winexe_status_event")

cpp_path.write_text(cpp, encoding="utf-8")

support_h = root / "support.h"
sh = support_h.read_text(encoding="utf-8", errors="replace")
if "support/winexe/winexe.h" not in sh:
    sh2, n = re.subn(
        r'(#include "support/x86/x86.h"\n)',
        r'\1\n// WinEXE support\n#include "support/winexe/winexe.h"\n',
        sh,
        count=1,
    )
    must(n == 1, "support.h: x86 include not found")
    support_h.write_text(sh2, encoding="utf-8")
    print("patched support.h")
else:
    print("already patched support.h")
PY

echo "WinEXE hook applied in $MAIN"
