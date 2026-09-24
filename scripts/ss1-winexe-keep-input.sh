#!/bin/sh
# Keep Pixart mouse (event0) and SIGMA keyboard (event1) un-grabbed while a
# WinEXE core is loaded, except while the MiSTer OSD is visible.
#
# Main's input_switch(-1) on OSD open/close does:
#   ioctl(fd, EVIOCGRAB, (grabbed | osd_visible) ? 1 : 0)
# grabbed stays 1 for any loaded core, so OSD *close* re-grabs USB and Xorg
# goes silent. Pico IR (event4/event5) is left grabbed for OSD control.
#
# Usage:
#   ss1-winexe-keep-input.sh          # one-shot ungrab (same as ungrab script)
#   ss1-winexe-keep-input.sh watch    # daemon until core is not WinEXE*
#   ss1-winexe-keep-input.sh stop
set -e
WIN="${WIN:-/media/fat/games/WinEXE}"
MOUSE="${SS1_MOUSE_EVENT:-/dev/input/event0}"
KBD="${SS1_KBD_EVENT:-/dev/input/event1}"
PIDFILE=/tmp/ss1-winexe-keep-input.pid
LOG="${SS1_KEEPINPUT_LOG:-$WIN/logs/ss1-winexe-keep-input.log}"
MODE=${1:-once}

if [ "$MODE" = stop ]; then
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
  for pid in $(ps | awk '/ss1-winexe-keep-input/{print $1}'); do
    kill "$pid" 2>/dev/null || true
  done
  exit 0
fi

if [ "$MODE" = watch ]; then
  mkdir -p "$(dirname "$LOG")"
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "keep-input already running pid=$(cat "$PIDFILE")"
    exit 0
  fi
  setsid "$0" watch-loop </dev/null >>"$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  echo "keep-input pid=$! log=$LOG"
  exit 0
fi

python3 - "$MODE" "$MOUSE" "$KBD" << 'PY'
import fcntl, os, subprocess, sys, time

EVIOCGRAB = 0x40044590
mode = sys.argv[1]
targets = sys.argv[2:]

def mister_pid():
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            cmd = open("/proc/%s/cmdline" % d, "rb").read().replace(b"\0", b" ").decode("latin1")
        except OSError:
            continue
        if cmd.startswith("/media/fat/MiSTer ") or cmd.startswith("/media/fat/MiSTer_WinEXE"):
            return int(d)
    return None

def core_name():
    try:
        return open("/tmp/CORENAME", "r").read().strip()
    except OSError:
        return ""

def winexe_core():
    n = core_name()
    return n.startswith("WinEXE")

def osd_visible():
    return os.path.exists("/tmp/OSD_VISIBLE")

def mister_fds(pid):
    fds = {}
    try:
        names = os.listdir("/proc/%d/fd" % pid)
    except OSError:
        return fds
    for fd in names:
        try:
            path = os.readlink("/proc/%d/fd/%s" % (pid, fd))
        except OSError:
            continue
        if path in targets:
            fds[path] = fd
    return fds

def grab_held(path):
    """True if some client (Main) holds EVIOCGRAB.
    If the device is free this briefly takes and drops grab (~microseconds)."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return False
    try:
        fcntl.ioctl(fd, EVIOCGRAB, 1)
        fcntl.ioctl(fd, EVIOCGRAB, 0)
        return False
    except OSError:
        return True
    finally:
        os.close(fd)

def ungrab():
    pid = mister_pid()
    if pid is None:
        print("no MiSTer process; nothing to ungrab")
        sys.stdout.flush()
        return False
    fds = mister_fds(pid)
    if not fds:
        print("MiSTer pid=%d has no matching input fds" % pid)
        sys.stdout.flush()
        return False
    ex = ["gdb", "--batch", "-p", str(pid), "-ex", "set pagination off"]
    for path, fd in sorted(fds.items()):
        ex += ["-ex", "call (int)ioctl(%s, 0x40044590, 0)" % fd]
        print("ungrab %s via MiSTer pid=%d fd=%s" % (path, pid, fd))
    ex += ["-ex", "detach", "-ex", "quit"]
    r = subprocess.run(ex, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    sys.stdout.flush()
    if r.returncode != 0:
        sys.stderr.write(r.stdout)
        return False
    print("ungrab_ok")
    sys.stdout.flush()
    return True

def any_held():
    return any(grab_held(p) for p in targets)

if mode in ("once", "watch-loop"):
    if mode == "once":
        ungrab()
        sys.exit(0)

    print("keep-input watch core=%r" % core_name())
    sys.stdout.flush()
    ungrab()
    last_osd = False
    saw_osd_file = False
    while True:
        if not winexe_core():
            print("core=%r not WinEXE; keep-input exiting" % core_name())
            sys.stdout.flush()
            break
        osd = osd_visible()
        if osd:
            saw_osd_file = True
            last_osd = True
        elif last_osd:
            ungrab()
            last_osd = False
        elif not saw_osd_file and any_held():
            # This Main build may not create /tmp/OSD_VISIBLE; still
            # release USB after OSD close re-grabs.
            ungrab()
        time.sleep(0.25)
PY
