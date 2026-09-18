#!/bin/sh
# FreeCell-only: wait until the FreeCell window is mapped, then F2 so launch
# opens a dealt game. Profile-only; does not change Wine, Box86, presenter,
# FPGA, or freecell.exe.
set +e
WIN="${WIN:-/media/fat/Windows}"
export HOME="${HOME:-/root}"
export DISPLAY="${DISPLAY:-:0}"
if [ -f "$WIN/bin/ss1-x11-env.sh" ]; then
  # shellcheck disable=SC1091
  . "$WIN/bin/ss1-x11-env.sh"
fi
export DISPLAY=:0

python3 - << 'PY'
import ctypes, os, struct, time
from ctypes import POINTER, c_void_p, c_ulong, c_uint, c_int, c_long, Structure, byref

class XA(Structure):
    _fields_ = [
        ("x", c_int), ("y", c_int), ("width", c_int), ("height", c_int),
        ("border_width", c_int), ("depth", c_int), ("visual", c_void_p),
        ("root", c_ulong), ("class", c_int), ("bit_gravity", c_int),
        ("win_gravity", c_int), ("backing_store", c_int),
        ("backing_planes", c_ulong), ("backing_pixel", c_ulong),
        ("save_under", c_int), ("colormap", c_ulong), ("map_installed", c_int),
        ("map_state", c_int), ("all_event_masks", c_long),
        ("your_event_mask", c_long), ("do_not_propagate_mask", c_long),
        ("override_redirect", c_int), ("screen", c_void_p),
    ]

def comm_alive():
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            if open("/proc/%s/comm" % d).read().strip() == "freecell.exe":
                return True
        except OSError:
            continue
    return False

t0 = time.time()
while time.time() - t0 < 10:
    if comm_alive():
        break
    time.sleep(0.1)
else:
    raise SystemExit(0)

X = ctypes.CDLL("/media/fat/Windows/x11/lib/libX11.so.6")
X.XOpenDisplay.restype = c_void_p
X.XDefaultRootWindow.restype = c_ulong
X.XDefaultRootWindow.argtypes = [c_void_p]
X.XQueryTree.restype = c_int
X.XQueryTree.argtypes = [
    c_void_p, c_ulong, POINTER(c_ulong), POINTER(c_ulong),
    POINTER(c_void_p), POINTER(c_uint),
]
X.XGetWindowAttributes.argtypes = [c_void_p, c_ulong, POINTER(XA)]
X.XQueryPointer.restype = c_int
X.XQueryPointer.argtypes = [
    c_void_p, c_ulong, POINTER(c_ulong), POINTER(c_ulong),
    POINTER(c_int), POINTER(c_int), POINTER(c_int), POINTER(c_int), POINTER(c_uint),
]
dpy = X.XOpenDisplay(None)
if not dpy:
    raise SystemExit(0)
root = X.XDefaultRootWindow(dpy)

def kids(w):
    rr = c_ulong(); pr = c_ulong(); ch = c_void_p(); n = c_uint()
    if not X.XQueryTree(dpy, w, byref(rr), byref(pr), byref(ch), byref(n)):
        return []
    if not n.value or not ch.value:
        return []
    ptr = ctypes.cast(ch, POINTER(c_ulong))
    return [int(ptr[i]) for i in range(n.value)]

def attr(w):
    a = XA()
    if X.XGetWindowAttributes(dpy, w, byref(a)) == 0:
        return None
    return a

def desktop():
    for w in kids(root):
        a = attr(w)
        if a and a.map_state == 2 and a.width == 640 and a.height == 480:
            return w
    return None

def app_child():
    d = desktop()
    if not d:
        return None
    for c in kids(d):
        a = attr(c)
        if a and a.map_state == 2 and a.width >= 400 and a.height >= 280:
            return c
    return None

t1 = time.time()
while time.time() - t1 < 10:
    if app_child():
        break
    time.sleep(0.15)
else:
    X.XCloseDisplay(dpy)
    raise SystemExit(0)

time.sleep(0.8)
if not comm_alive():
    X.XCloseDisplay(dpy)
    raise SystemExit(0)

EV_SYN, EV_KEY, EV_REL = 0, 1, 2
REL_X, REL_Y, BTN_LEFT, KEY_F2 = 0x00, 0x01, 0x110, 60

def pack(t, c, v):
    return struct.pack("llHHi", 0, 0, t, c, v)

def write_events(dev, events):
    fd = os.open(dev, os.O_WRONLY)
    os.write(fd, b"".join(pack(t, c, v) for t, c, v in events))
    os.close(fd)

def pointer():
    rr = c_ulong(); child = c_ulong()
    rx = c_int(); ry = c_int(); wx = c_int(); wy = c_int(); mask = c_uint()
    X.XQueryPointer(
        dpy, root, byref(rr), byref(child), byref(rx), byref(ry),
        byref(wx), byref(wy), byref(mask),
    )
    return rx.value, ry.value

def rel_move(dx, dy):
    while dx or dy:
        sx = max(-127, min(127, dx))
        sy = max(-127, min(127, dy))
        write_events("/dev/input/event0", [
            (EV_REL, REL_X, sx), (EV_REL, REL_Y, sy), (EV_SYN, 0, 0),
        ])
        dx -= sx
        dy -= sy
        time.sleep(0.008)

tx, ty = 220, 12
for _ in range(4):
    cx, cy = pointer()
    if abs(cx - tx) <= 2 and abs(cy - ty) <= 2:
        break
    rel_move(tx - cx, ty - cy)
    time.sleep(0.05)
write_events("/dev/input/event0", [(EV_KEY, BTN_LEFT, 1), (EV_SYN, 0, 0)])
time.sleep(0.07)
write_events("/dev/input/event0", [(EV_KEY, BTN_LEFT, 0), (EV_SYN, 0, 0)])
time.sleep(0.25)
write_events("/dev/input/event1", [(EV_KEY, KEY_F2, 1), (EV_SYN, 0, 0)])
time.sleep(0.06)
write_events("/dev/input/event1", [(EV_KEY, KEY_F2, 0), (EV_SYN, 0, 0)])
X.XCloseDisplay(dpy)
PY
exit 0
