#!/bin/sh
# Present /dev/fb0 onto the HPS buffer the Menu core is already scanning.
#
# On SuperStation / MiSTer, Linux /dev/fb0 is framebuffer n=0 at
# FB_ADDR+4096. The Menu wallpaper path scanouts n=1
# (FB_ADDR + 1920*1080*4). Writing Xorg/Wine into /dev/fb0 therefore does
# not change the physical HDMI image until either:
#   - Main calls video_fb_enable(1, 0)  (F9 / Scripts / docs viewer)
#   - or this presenter copies n=0 onto n=1
#
# This script does the copy. It does not change Wine, Box86, or the prefix.
# It does not send input.
#
# Usage:
#   ss1-fb-present.sh once
#   ss1-fb-present.sh loop [seconds]   # seconds=0 means forever
set -e

MODE="${1:-once}"
SECONDS_RUN="${2:-0}"

python3 - << PY
import mmap, os, sys, time

FB_ADDR = 0x22000000
W, H = 1920, 1080
BUF = W * H * 4
N1 = BUF
LOG = os.environ.get("SS1_PRESENT_LOG", "/media/fat/Windows/logs/ss1-present.log")

def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = "%s pid=%d %s\n" % (ts, os.getpid(), msg)
    sys.stdout.write(line)
    sys.stdout.flush()
    try:
        with open(LOG, "a") as f:
            f.write(line)
    except Exception:
        pass

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
mm = mmap.mmap(fd, BUF * 3 + 8192, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=FB_ADDR)
fb = os.open("/dev/fb0", os.O_RDONLY)

def present():
    os.lseek(fb, 0, os.SEEK_SET)
    data = os.read(fb, BUF)
    if len(data) != BUF:
        raise SystemExit("short /dev/fb0 read: %d" % len(data))
    mm[N1:N1 + BUF] = data

mode = "$MODE"
seconds = float("$SECONDS_RUN")
log("start mode=%s seconds=%s" % (mode, seconds))
if mode == "loop":
    end = None if seconds <= 0 else time.time() + seconds
    n = 0
    while end is None or time.time() < end:
        present()
        n += 1
        if n == 1 or n % 50 == 0:
            log("frames=%d" % n)
        time.sleep(0.15)
    log("loop_end frames=%d" % n)
else:
    present()
    log("presented_once")

os.close(fb)
mm.close()
os.close(fd)
PY
