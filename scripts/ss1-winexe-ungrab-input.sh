#!/bin/sh
# Release Main's exclusive EVIOCGRAB on the USB mouse/keyboard only.
# WinEXE_Test leaves Main grabbing event0/event1, so dummy Xorg can attach
# those devices but never sees motion/keys. Menu+F9 used to call
# input_switch(0); we cannot do that here because it enables Linux n=0 HDMI.
# Does not change the FPGA core, dummy driver, or presenter.
set -e
MOUSE="${SS1_MOUSE_EVENT:-/dev/input/event0}"
KBD="${SS1_KBD_EVENT:-/dev/input/event1}"

python3 - "$MOUSE" "$KBD" << 'PY'
import os, subprocess, sys

targets = set(sys.argv[1:])
pid = None
for d in os.listdir("/proc"):
    if not d.isdigit():
        continue
    try:
        cmd = open("/proc/%s/cmdline" % d, "rb").read().replace(b"\0", b" ").decode("latin1")
    except OSError:
        continue
    if cmd.startswith("/media/fat/MiSTer ") or cmd.startswith("/media/fat/MiSTer_WinEXE"):
        pid = int(d)
        break
if pid is None:
    print("no MiSTer process; nothing to ungrab")
    sys.exit(0)

fds = {}
for fd in os.listdir("/proc/%d/fd" % pid):
    try:
        path = os.readlink("/proc/%d/fd/%s" % (pid, fd))
    except OSError:
        continue
    if path in targets:
        fds[path] = fd

if not fds:
    print("MiSTer pid=%d has no matching input fds" % pid)
    sys.exit(0)

ex = ["gdb", "--batch", "-p", str(pid), "-ex", "set pagination off"]
for path, fd in sorted(fds.items()):
    # EVIOCGRAB = _IOW('E', 0x90, int) = 0x40044590
    ex += ["-ex", "call (int)ioctl(%s, 0x40044590, 0)" % fd]
    print("ungrab %s via MiSTer pid=%d fd=%s" % (path, pid, fd))
ex += ["-ex", "detach", "-ex", "quit"]
r = subprocess.run(ex, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
if r.returncode != 0:
    sys.stderr.write(r.stdout)
    sys.exit(r.returncode)
print("ungrab_ok")
PY
