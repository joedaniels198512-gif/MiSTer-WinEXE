#!/bin/sh
# SC2K-only: keep the floating tool palette above the city map without
# activating it. Does not touch presenter, FPGA, or global Wine graphics.
#
#   ss1-winexe-sc2k-toolbar.sh watch
#   ss1-winexe-sc2k-toolbar.sh stop
set +e
WIN="${WIN:-/media/fat/games/WinEXE}"
PIDFILE=/tmp/ss1-winexe-sc2k-toolbar.pid
LOG="${SS1_SC2K_TB_LOG:-$WIN/logs/ss1-winexe-sc2k-toolbar.log}"
MODE=${1:-watch}

if [ "$MODE" = stop ]; then
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
  for d in /proc/[0-9]*; do
    comm=$(cat "$d/comm" 2>/dev/null) || continue
    case "$comm" in
      ss1-winexe-sc2k-*) kill "${d#/proc/}" 2>/dev/null || true ;;
    esac
  done
  exit 0
fi

if [ "$MODE" = watch ]; then
  mkdir -p "$(dirname "$LOG")"
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "sc2k-toolbar already running pid=$(cat "$PIDFILE")"
    exit 0
  fi
  export DISPLAY="${DISPLAY:-:0}"
  . "$WIN/bin/ss1-x11-env.sh"
  setsid "$0" watch-loop </dev/null >>"$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  echo "sc2k-toolbar pid=$! log=$LOG"
  exit 0
fi

# watch-loop
python3 - << 'PY'
import ctypes, os, select, time
from ctypes import c_void_p, c_ulong, c_int, c_uint, c_char, POINTER, Structure

CWSibling = 1 << 5
CWStackMode = 1 << 6
Above = 0
StructureNotifyMask = 1 << 17
SubstructureNotifyMask = 1 << 19
ConfigureNotify = 22
CirculateNotify = 26
MapNotify = 19
UnmapNotify = 18

class XA(Structure):
    _fields_ = [
        ("x", c_int), ("y", c_int), ("width", c_int), ("height", c_int),
        ("border_width", c_int), ("depth", c_int),
        ("visual", c_void_p), ("root", c_ulong),
        ("c_class", c_int), ("bit_gravity", c_int), ("win_gravity", c_int),
        ("backing_store", c_int), ("backing_planes", c_ulong), ("backing_pixel", c_ulong),
        ("save_under", c_int), ("colormap", c_ulong), ("map_installed", c_int),
        ("map_state", c_int), ("all_event_masks", c_ulong), ("your_event_mask", c_ulong),
        ("do_not_propagate_mask", c_ulong), ("override_redirect", c_int), ("screen", c_void_p),
    ]

class XWindowChanges(Structure):
    _fields_ = [
        ("x", c_int), ("y", c_int), ("width", c_int), ("height", c_int),
        ("border_width", c_int), ("sibling", c_ulong), ("stack_mode", c_int),
    ]

class XEvent(Structure):
    _fields_ = [("pad", c_char * 192)]

X = ctypes.CDLL("/media/fat/games/WinEXE/x11/lib/libX11.so.6")
X.XOpenDisplay.restype = c_void_p
X.XDefaultRootWindow.restype = c_ulong
X.XDefaultRootWindow.argtypes = [c_void_p]
X.XQueryTree.restype = c_int
X.XQueryTree.argtypes = [c_void_p, c_ulong, POINTER(c_ulong), POINTER(c_ulong),
                         POINTER(c_void_p), POINTER(c_uint)]
X.XGetWindowAttributes.argtypes = [c_void_p, c_ulong, POINTER(XA)]
X.XConfigureWindow.argtypes = [c_void_p, c_ulong, c_uint, POINTER(XWindowChanges)]
X.XSelectInput.argtypes = [c_void_p, c_ulong, c_ulong]
X.XPending.argtypes = [c_void_p]
X.XNextEvent.argtypes = [c_void_p, POINTER(XEvent)]
X.XFlush.argtypes = [c_void_p]
X.XConnectionNumber.argtypes = [c_void_p]
X.XGetInputFocus.argtypes = [c_void_p, POINTER(c_ulong), POINTER(c_int)]
X.XSetInputFocus.argtypes = [c_void_p, c_ulong, c_int, c_ulong]
RevertToParent = 2
CurrentTime = 0

def simcity_alive():
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            if open("/proc/%s/comm" % d).read().strip() == "SIMCITY.EXE":
                return True
        except OSError:
            continue
    return False

dpy = X.XOpenDisplay(None)
if not dpy:
    raise SystemExit("XOpenDisplay failed")
root = X.XDefaultRootWindow(dpy)

def kids(w):
    rr = c_ulong(); pr = c_ulong(); ch = c_void_p(); n = c_uint()
    if not X.XQueryTree(dpy, w, ctypes.byref(rr), ctypes.byref(pr),
                        ctypes.byref(ch), ctypes.byref(n)):
        return []
    if not n.value or not ch.value:
        return []
    ptr = ctypes.cast(ch, POINTER(c_ulong))
    return [int(ptr[i]) for i in range(n.value)]

def attr(w):
    a = XA()
    if X.XGetWindowAttributes(dpy, w, ctypes.byref(a)) == 0:
        return None
    return a

def desktop():
    for w in kids(root):
        a = attr(w)
        if a and a.width == 640 and a.height == 480 and a.map_state == 2:
            return w
    return None

def classify(desk):
    mapped = []
    for w in kids(desk):
        a = attr(w)
        if not a or a.map_state != 2:
            continue
        mapped.append((w, a.width, a.height, a.x, a.y))
    palette = None
    city = None
    city_area = 0
    for w, ww, hh, x, y in mapped:
        if 50 <= ww <= 130 and 280 <= hh <= 460:
            palette = w
        if ww >= 400 and hh >= 280:
            area = ww * hh
            if area > city_area:
                city = w
                city_area = area
    return mapped, city, palette

def restack_palette_above_map(desk, city, palette):
    order = kids(desk)
    try:
        ip = order.index(palette)
        ic = order.index(city)
    except ValueError:
        return False
    others_above_city = []
    for w in order[ic + 1:]:
        if w == palette:
            continue
        a = attr(w)
        if a and a.map_state == 2 and a.width > 8 and a.height > 8:
            others_above_city.append(w)
    if others_above_city:
        return False
    if ip > ic:
        return False
    focus_w = c_ulong(); focus_r = c_int()
    X.XGetInputFocus(dpy, ctypes.byref(focus_w), ctypes.byref(focus_r))
    ch = XWindowChanges()
    ch.sibling = city
    ch.stack_mode = Above
    X.XConfigureWindow(dpy, palette, CWSibling | CWStackMode, ctypes.byref(ch))
    X.XFlush(dpy)
    focus2 = c_ulong(); rev2 = c_int()
    X.XGetInputFocus(dpy, ctypes.byref(focus2), ctypes.byref(rev2))
    if focus2.value != focus_w.value and focus_w.value:
        X.XSetInputFocus(dpy, focus_w.value, RevertToParent, CurrentTime)
        X.XFlush(dpy)
    print("raise palette=0x%x above map=0x%x (focus kept 0x%x)" % (
        palette, city, focus_w.value), flush=True)
    return True

desk = None
for _ in range(90):
    if simcity_alive():
        break
    time.sleep(1)
for _ in range(90):
    desk = desktop()
    if desk:
        break
    time.sleep(0.5)
if not desk:
    raise SystemExit("wine desktop not found")

X.XSelectInput(dpy, desk, SubstructureNotifyMask)
X.XFlush(dpy)
fd = X.XConnectionNumber(dpy)
print("watch desktop=0x%x" % desk, flush=True)
last = 0.0
while simcity_alive():
    timeout = 0.25
    try:
        r, _, _ = select.select([fd], [], [], timeout)
    except (select.error, OSError):
        break
    if r:
        while X.XPending(dpy):
            ev = XEvent()
            X.XNextEvent(dpy, ctypes.byref(ev))
    now = time.time()
    if now - last < 0.12:
        continue
    last = now
    d = desktop()
    if not d:
        continue
    if d != desk:
        desk = d
        X.XSelectInput(dpy, desk, SubstructureNotifyMask)
    mapped, city, palette = classify(desk)
    if city and palette:
        restack_palette_above_map(desk, city, palette)

print("SIMCITY.EXE gone; exit", flush=True)
X.XCloseDisplay(dpy)
PY
