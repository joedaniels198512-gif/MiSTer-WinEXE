#!/usr/bin/env python3
"""Cold-start timeline + pixel dumps for one WinEXE .WEX launch.

Does not change presenter capture. Samples:
  A) X root (same drawable the presenter XShmGetImage uses)
  B) largest mapped child (Wine desktop / app)
  C) FPGA FB at 0x30000000 (post-copy destination)
"""
from __future__ import print_function

import ctypes
import os
import struct
import sys
import time

WIN = os.environ.get("WIN", "/media/fat/Windows")
T0_PATH = "/tmp/ss1-wex-t0"
LOG = os.path.join(WIN, "logs/wex-timeline.log")
DIAG = os.path.join(WIN, "logs/wex-diag")
FB_PHYS = 0x30000000
FB_W, FB_H, FB_BPP = 640, 480, 4
FB_SIZE = FB_W * FB_H * FB_BPP
ROOT_BLUE_BGRX = (0x80, 0x00, 0x00, 0x00)  # xsetroot #000080
POLL = 0.05
MAX_S = 180.0

os.environ.setdefault("DISPLAY", ":0")
_XLIB = WIN + "/x11/lib"
_HOSTLIB = WIN + "/host-libs/lib"
os.environ["LD_LIBRARY_PATH"] = (
    _XLIB + ":" + _HOSTLIB + ":" + os.environ.get("LD_LIBRARY_PATH", "")
)


def _preload_xlibs():
    """dlopen deps by absolute path. The linker does not reread LD_LIBRARY_PATH."""
    for name in (
        "libXau.so.6",
        "libXdmcp.so.6",
        "libxcb.so.1",
        "libXext.so.6",
        "libXfixes.so.3",
    ):
        for d in (_XLIB, _HOSTLIB):
            p = os.path.join(d, name)
            if os.path.isfile(p):
                try:
                    ctypes.CDLL(p, mode=ctypes.RTLD_GLOBAL)
                except OSError:
                    pass
                break


def t0():
    try:
        return float(open(T0_PATH).read().strip())
    except Exception:
        return time.monotonic()


def tms():
    return int((time.monotonic() - t0()) * 1000)


def log(msg):
    line = "t=%sms %s" % (tms(), msg)
    sys.stdout.write(line + "\n")
    sys.stdout.flush()
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def comm_pids():
    found = {}
    try:
        names = os.listdir("/proc")
    except OSError:
        return found
    for n in names:
        if not n.isdigit():
            continue
        try:
            c = open("/proc/%s/comm" % n).read().strip()
        except OSError:
            continue
        found.setdefault(c, n)
    return found


def load_x11():
    _preload_xlibs()
    x11 = ctypes.CDLL(_XLIB + "/libX11.so.6", mode=ctypes.RTLD_GLOBAL)
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    return x11


class XWindowAttributes(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_int), ("y", ctypes.c_int),
        ("width", ctypes.c_int), ("height", ctypes.c_int),
        ("border_width", ctypes.c_int), ("depth", ctypes.c_int),
        ("visual", ctypes.c_void_p), ("root", ctypes.c_ulong),
        ("class", ctypes.c_int), ("bit_gravity", ctypes.c_int),
        ("win_gravity", ctypes.c_int), ("backing_store", ctypes.c_int),
        ("backing_planes", ctypes.c_ulong), ("backing_pixel", ctypes.c_ulong),
        ("save_under", ctypes.c_int), ("colormap", ctypes.c_ulong),
        ("map_installed", ctypes.c_int), ("map_state", ctypes.c_int),
        ("all_event_masks", ctypes.c_long), ("your_event_mask", ctypes.c_long),
        ("do_not_propagate_mask", ctypes.c_long), ("override_redirect", ctypes.c_int),
        ("screen", ctypes.c_void_p),
    ]


def x_setup(x11):
    dpy = x11.XOpenDisplay(None)
    if not dpy:
        return None
    x11.XDefaultRootWindow.restype = ctypes.c_ulong
    x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    x11.XDefaultDepth.argtypes = [ctypes.c_void_p, ctypes.c_int]
    x11.XDefaultScreen.argtypes = [ctypes.c_void_p]
    x11.XDisplayWidth.argtypes = [ctypes.c_void_p, ctypes.c_int]
    x11.XDisplayHeight.argtypes = [ctypes.c_void_p, ctypes.c_int]
    x11.XQueryTree.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong,
        ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong),
        ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)), ctypes.POINTER(ctypes.c_uint),
    ]
    x11.XGetWindowAttributes.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(XWindowAttributes)
    ]
    x11.XGetImage.restype = ctypes.c_void_p
    x11.XGetImage.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
        ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_int,
    ]
    x11.XDestroyImage.argtypes = [ctypes.c_void_p]
    return dpy


class XImage(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_int), ("height", ctypes.c_int),
        ("xoffset", ctypes.c_int), ("format", ctypes.c_int),
        ("data", ctypes.c_void_p),
        ("byte_order", ctypes.c_int), ("bitmap_unit", ctypes.c_int),
        ("bitmap_bit_order", ctypes.c_int), ("bitmap_pad", ctypes.c_int),
        ("depth", ctypes.c_int), ("bytes_per_line", ctypes.c_int),
        ("bits_per_pixel", ctypes.c_int),
        ("red_mask", ctypes.c_ulong), ("green_mask", ctypes.c_ulong),
        ("blue_mask", ctypes.c_ulong),
    ]


def walk_mapped(x11, dpy, win, out, depth=0):
    attr = XWindowAttributes()
    if x11.XGetWindowAttributes(dpy, win, ctypes.byref(attr)) == 0:
        return
    out.append((win, attr.width, attr.height, attr.x, attr.y, attr.map_state,
                attr.override_redirect, attr.depth, depth))
    root_r = ctypes.c_ulong()
    parent = ctypes.c_ulong()
    children = ctypes.POINTER(ctypes.c_ulong)()
    n = ctypes.c_uint()
    if x11.XQueryTree(dpy, win, ctypes.byref(root_r), ctypes.byref(parent),
                      ctypes.byref(children), ctypes.byref(n)) == 0:
        return
    for i in range(n.value):
        walk_mapped(x11, dpy, children[i], out, depth + 1)


def pixel_stats(buf, nbytes):
    """Return (n_non_root_blue, n_px, sample_unique_approx)."""
    n = nbytes // 4
    non = 0
    seen = set()
    step = max(1, n // 4000)
    for i in range(0, n, 1 if n < 50000 else step):
        o = i * 4
        b, g, r = buf[o], buf[o + 1], buf[o + 2]
        if (b, g, r) != (ROOT_BLUE_BGRX[0], ROOT_BLUE_BGRX[1], ROOT_BLUE_BGRX[2]):
            non += 1
        if len(seen) < 64:
            seen.add((b, g, r))
    # scale if sampled
    if step > 1:
        non = int(non * step)
        if non > n:
            non = n
    return non, n, len(seen)


def write_ppm(path, w, h, bgrx, nbytes):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(("P6\n%d %d\n255\n" % (w, h)).encode("ascii"))
        n = min(nbytes, w * h * 4)
        rgb = bytearray(w * h * 3)
        di = 0
        for i in range(0, n, 4):
            b, g, r = bgrx[i], bgrx[i + 1], bgrx[i + 2]
            rgb[di] = r
            rgb[di + 1] = g
            rgb[di + 2] = b
            di += 3
        f.write(bytes(rgb[:di]))


def ximage_bytes(x11, dpy, drawable, w, h):
    ZPixmap = 2
    AllPlanes = 0xFFFFFFFF
    p = x11.XGetImage(dpy, drawable, 0, 0, w, h, AllPlanes, ZPixmap)
    if not p:
        return None
    im = XImage.from_address(p)
    if not im.data:
        return None
    nbytes = im.bytes_per_line * im.height
    buf = ctypes.string_at(im.data, nbytes)
    # If bpl != w*4, pack. Dummy is 2560.
    if im.bytes_per_line == w * 4:
        packed = buf[: w * h * 4]
    else:
        packed = bytearray(w * h * 4)
        for y in range(h):
            s = y * im.bytes_per_line
            d = y * w * 4
            packed[d:d + w * 4] = buf[s:s + w * 4]
        packed = bytes(packed)
    x11.XDestroyImage(ctypes.c_void_p(p))
    return packed, im.depth, im.bits_per_pixel


def mmap_fb():
    libc = ctypes.CDLL("libc.so.6")
    libc.mmap.restype = ctypes.c_void_p
    libc.mmap.argtypes = [
        ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int,
        ctypes.c_int, ctypes.c_long,
    ]
    fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
    addr = libc.mmap(None, FB_SIZE, 1, 1, fd, FB_PHYS)
    os.close(fd)
    if not addr or addr == ctypes.c_void_p(-1).value:
        return None, None
    return addr, libc


def presenter_shm_dump(prefix):
    """Copy the presenter's attached XShm buffer if it is still mapped."""
    pid = None
    try:
        for n in os.listdir("/proc"):
            if not n.isdigit():
                continue
            try:
                c = open("/proc/%s/comm" % n).read().strip()
            except OSError:
                continue
            if c.startswith("ss1-winexe-x11"):
                pid = n
                break
    except OSError:
        return
    if not pid:
        log("dump presenter SHM: presenter not running")
        return
    maps = []
    try:
        for line in open("/proc/%s/maps" % pid):
            maps.append(line.rstrip())
    except OSError as e:
        log("dump presenter SHM maps failed: %s" % e)
        return
    cand = []
    for line in maps:
        # 0012c000-00258000 rw-s 00000000 00:05 12345 /SYSV00000000 (deleted)
        parts = line.split()
        if len(parts) < 5:
            continue
        rng = parts[0]
        perms = parts[1]
        if "s" not in perms:
            continue
        try:
            a, b = rng.split("-")
            start = int(a, 16)
            end = int(b, 16)
        except ValueError:
            continue
        size = end - start
        if size < FB_SIZE or size > FB_SIZE * 4:
            continue
        cand.append((start, size, line))
    if not cand:
        log("dump presenter SHM: no SysV mapping near %d bytes pid=%s" % (FB_SIZE, pid))
        return
    start, size, line = cand[0]
    buf = None
    try:
        mem = open("/proc/%s/mem" % pid, "rb")
        mem.seek(start)
        buf = mem.read(FB_SIZE)
        mem.close()
    except OSError:
        buf = None
    if buf is None or len(buf) < FB_SIZE:
        class iovec(ctypes.Structure):
            _fields_ = [("base", ctypes.c_void_p), ("len", ctypes.c_size_t)]
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        raw = ctypes.create_string_buffer(FB_SIZE)
        local = iovec(ctypes.cast(raw, ctypes.c_void_p), FB_SIZE)
        remote = iovec(start, FB_SIZE)
        libc.process_vm_readv.restype = ctypes.c_ssize_t
        n = libc.process_vm_readv(int(pid), ctypes.byref(local), 1, ctypes.byref(remote), 1, 0)
        if n == FB_SIZE:
            buf = raw.raw
            log("dump presenter SHM via process_vm_readv pid=%s" % pid)
        else:
            log("dump presenter SHM /proc/%s/mem and process_vm_readv failed n=%s" % (pid, n))
            return
    if len(buf) < FB_SIZE:
        log("dump presenter SHM short read %d" % len(buf))
        return
    non, n, uniq = pixel_stats(buf, FB_SIZE)
    write_ppm(prefix + "_Csrc_presenter_shm.ppm", FB_W, FB_H, buf, FB_SIZE)
    log("dump presenter SHM pid=%s va=0x%x size=%d non_root_px=%d/%d uniq~%d line=%s" % (
        pid, start, size, non, n, uniq, line[:80]))


def dump_all(x11, dpy, root, desktop, notepad, tag):
    os.makedirs(DIAG, exist_ok=True)
    prefix = os.path.join(DIAG, "%s_t%sms" % (tag, tms()))
    log("presenter XShmGetImage target drawable=0x%x (DefaultRootWindow) %dx%d — capture unchanged" % (
        root, FB_W, FB_H))
    log("IDs root=0x%x wine_desktop=0x%x notepad=0x%x target=0x%x" % (
        root, desktop or 0, notepad or 0, root))
    presenter_shm_dump(prefix)
    # A root
    got = ximage_bytes(x11, dpy, root, FB_W, FB_H)
    if got:
        buf, depth, bpp = got
        non, n, uniq = pixel_stats(buf, len(buf))
        write_ppm(prefix + "_A_root.ppm", FB_W, FB_H, buf, len(buf))
        log("dump A root=0x%x depth=%d bpp=%d non_root_px=%d/%d uniq~%d file=%s_A_root.ppm" % (
            root, depth, bpp, non, n, uniq, prefix))
        first_non = non > n * 0.02
    else:
        log("dump A root XGetImage FAILED")
        first_non = False
        buf = None
    # B Wine desktop and Notepad child (hierarchy, not the presenter target)
    for label, target in (("desktop", desktop), ("notepad", notepad)):
        if not target:
            continue
        attr = XWindowAttributes()
        if x11.XGetWindowAttributes(dpy, target, ctypes.byref(attr)) == 0:
            log("dump B %s=0x%x XGetWindowAttributes FAILED" % (label, target))
            continue
        w, h = attr.width, attr.height
        if w < 2:
            w = FB_W
        if h < 2:
            h = FB_H
        gotb = ximage_bytes(x11, dpy, target, w, h)
        if gotb:
            bbuf, d, bp = gotb
            non, n, uniq = pixel_stats(bbuf, len(bbuf))
            write_ppm(prefix + "_B_%s.ppm" % label, w, h, bbuf, len(bbuf))
            log("dump B %s=0x%x %dx%d depth=%d map=%d ov=%d non_root_px=%d/%d uniq~%d file=%s_B_%s.ppm" % (
                label, target, w, h, d, attr.map_state, attr.override_redirect,
                non, n, uniq, prefix, label))
        else:
            log("dump B %s=0x%x XGetImage FAILED" % (label, target))
    # keep B_win.ppm as the app window for the original contract
    app = notepad or desktop
    if app:
        attr = XWindowAttributes()
        if x11.XGetWindowAttributes(dpy, app, ctypes.byref(attr)) != 0:
            w, h = max(attr.width, 2), max(attr.height, 2)
            gotb = ximage_bytes(x11, dpy, app, w, h)
            if gotb:
                bbuf, d, bp = gotb
                write_ppm(prefix + "_B_win.ppm", w, h, bbuf, len(bbuf))
                log("dump B_win alias drawable=0x%x %dx%d" % (app, w, h))
            else:
                log("dump B_win XGetImage FAILED")
    # C FPGA destination
    addr, libc = mmap_fb()
    if addr:
        fbbuf = ctypes.string_at(addr, FB_SIZE)
        non, n, uniq = pixel_stats(fbbuf, FB_SIZE)
        write_ppm(prefix + "_C_fpga.ppm", FB_W, FB_H, fbbuf, FB_SIZE)
        log("dump C fpga=0x%x non_root_px=%d/%d uniq~%d file=%s_C_fpga.ppm" % (
            FB_PHYS, non, n, uniq, prefix))
        libc.munmap(ctypes.c_void_p(addr), FB_SIZE)
        if buf is not None:
            same = buf[:FB_SIZE] == fbbuf[: min(len(buf), FB_SIZE)]
            log("dump A_vs_C_identical=%s" % same)
    else:
        log("dump C mmap 0x30000000 FAILED")
    return first_non


def dump_now_once(x11):
    dpy = x_setup(x11)
    if not dpy:
        log("dump-now XOpenDisplay failed")
        return
    root = x11.XDefaultRootWindow(dpy)
    scr = x11.XDefaultScreen(dpy)
    log("dump-now root=0x%x %dx%d depth=%d (XShmGetImage target)" % (
        root, x11.XDisplayWidth(dpy, scr), x11.XDisplayHeight(dpy, scr),
        x11.XDefaultDepth(dpy, scr)))
    wins = []
    walk_mapped(x11, dpy, root, wins)
    desktop = notepad_win = 0
    for w, ww, hh, x, y, ms, ov, dep, depn in wins:
        log("tree id=0x%x %dx%d+%d+%d map=%d ov=%d depth=%d level=%d" % (
            w, ww, hh, x, y, ms, ov, dep, depn))
        if depn == 1 and ms == 2 and ww >= 600 and hh >= 400 and w != root:
            desktop = w
        elif ms == 2 and ww >= 200 and hh >= 150 and w not in (root, desktop):
            if not notepad_win:
                notepad_win = w
    dump_all(x11, dpy, root, desktop, notepad_win, "live")


def main():
    log("trace start pid=%d argv=%s" % (os.getpid(), " ".join(sys.argv)))
    if "--dump-now" in sys.argv:
        dump_now_once(load_x11())
        log("trace exit")
        return
    x11 = None
    for _ in range(40):
        try:
            x11 = load_x11()
            break
        except OSError as e:
            log("X11 load retry: %s" % e)
            time.sleep(0.25)
    if x11 is None:
        log("trace exit: cannot load libX11")
        return
    seen = {
        "xorg": False,
        "x_ready": False,
        "presenter": False,
        "wineserver": False,
        "explorer": False,
        "notepad": False,
        "desktop": False,
        "notepad_created": False,
        "notepad_win": False,
        "non_root_x": False,
        "non_root_fpga": False,
        "non_root_ui_x": False,
        "non_root_ui_fpga": False,
    }
    dumped = False
    root = desktop = notepad_win = 0
    dpy = None
    deadline = time.monotonic() + MAX_S
    while time.monotonic() < deadline:
        p = comm_pids()
        if not seen["xorg"] and "Xorg" in p:
            seen["xorg"] = True
            log("Xorg process started pid=%s" % p["Xorg"])
        if not seen["presenter"] and "ss1-winexe-x11-" in p:
            seen["presenter"] = True
            log("presenter started pid=%s" % p["ss1-winexe-x11-"])
        if not seen["wineserver"] and "wineserver" in p:
            seen["wineserver"] = True
            log("wineserver available pid=%s" % p["wineserver"])
        if not seen["explorer"] and "explorer.exe" in p:
            seen["explorer"] = True
            log("explorer.exe PID=%s" % p["explorer.exe"])
        if not seen["notepad"] and "notepad.exe" in p:
            seen["notepad"] = True
            log("notepad.exe PID=%s" % p["notepad.exe"])

        if dpy is None:
            dpy = x_setup(x11)
            if dpy:
                seen["x_ready"] = True
                root = x11.XDefaultRootWindow(dpy)
                scr = x11.XDefaultScreen(dpy)
                log("X display accepts clients X_READY=1 root=0x%x %dx%d depth=%d (presenter XShmGetImage target=root)" % (
                    root,
                    x11.XDisplayWidth(dpy, scr),
                    x11.XDisplayHeight(dpy, scr),
                    x11.XDefaultDepth(dpy, scr),
                ))
        if dpy:
            wins = []
            walk_mapped(x11, dpy, root, wins)
            # Wine desktop: 640x480 viewable child of root
            for w, ww, hh, x, y, ms, ov, dep, depn in wins:
                if depn == 1 and ms == 2 and ww >= 600 and hh >= 400 and w != root:
                    if not seen["desktop"]:
                        seen["desktop"] = True
                        desktop = w
                        log("Wine desktop X window mapped id=0x%x %dx%d+%d+%d depth=%d" % (
                            w, ww, hh, x, y, dep))
            # Notepad-like: created vs mapped. created = any map_state.
            for w, ww, hh, x, y, ms, ov, dep, depn in wins:
                if ww >= 200 and hh >= 150 and w not in (root, desktop):
                    if not seen["notepad_created"]:
                        seen["notepad_created"] = True
                        log("Notepad X window created id=0x%x %dx%d+%d+%d map_state=%d ov=%d depth=%d" % (
                            w, ww, hh, x, y, ms, ov, dep))
                    if ms == 2 and not seen["notepad_win"]:
                        seen["notepad_win"] = True
                        notepad_win = w
                        log("Notepad X window mapped/viewable id=0x%x %dx%d+%d+%d ov=%d depth=%d" % (
                            w, ww, hh, x, y, ov, dep))

            got = ximage_bytes(x11, dpy, root, FB_W, FB_H)
            if got:
                buf, _, _ = got
                non, n, uniq = pixel_stats(buf, len(buf))
                if (not seen["non_root_x"]) and non > n * 0.02:
                    seen["non_root_x"] = True
                    log("first X root frame with non-root pixels non=%d/%d uniq~%d" % (non, n, uniq))
                if (not seen.get("non_root_ui_x")) and uniq >= 8 and non > n * 0.02:
                    seen["non_root_ui_x"] = True
                    log("first X root UI frame (uniq>=8) non=%d/%d uniq~%d" % (non, n, uniq))

            addr, libc = mmap_fb()
            if addr:
                fbbuf = ctypes.string_at(addr, FB_SIZE)
                non, n, uniq = pixel_stats(fbbuf, FB_SIZE)
                if (not seen["non_root_fpga"]) and non > n * 0.02:
                    seen["non_root_fpga"] = True
                    log("first presenter/FPGA write with non-root pixels non=%d/%d uniq~%d" % (non, n, uniq))
                if (not seen.get("non_root_ui_fpga")) and uniq >= 8 and non > n * 0.02:
                    seen["non_root_ui_fpga"] = True
                    log("first presenter/FPGA UI write (uniq>=8) non=%d/%d uniq~%d" % (non, n, uniq))
                libc.munmap(ctypes.c_void_p(addr), FB_SIZE)

            if seen["notepad_win"] and not dumped:
                dump_all(x11, dpy, root, desktop, notepad_win, "mapped")
                dumped = True

        if seen["notepad_win"] and seen.get("non_root_ui_x") and seen.get("non_root_ui_fpga") and dumped:
            log("trace complete all milestones")
            break
        time.sleep(POLL)
    else:
        log("trace timeout seen=%s" % seen)
        if dpy and not dumped:
            dump_all(x11, dpy, root, desktop, notepad_win, "timeout")
    log("trace exit")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log("trace exception %s" % e)
        raise
