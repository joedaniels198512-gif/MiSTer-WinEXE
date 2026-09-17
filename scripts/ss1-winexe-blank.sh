#!/bin/sh
# Zero the WinEXE FPGA framebuffer at 0x30000000 (640×480 BGRX).
# Used for idle/black display after Xorg/presenter stop. No FPGA rebuild.
set +e
python3 - << 'PY'
import ctypes, os, sys

BASE = 0x30000000
SIZE = 640 * 480 * 4
PROT_READ, PROT_WRITE, MAP_SHARED = 1, 2, 1
MAP_FAILED = ctypes.c_void_p(-1).value

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
libc = ctypes.CDLL("libc.so.6")
libc.mmap.restype = ctypes.c_void_p
libc.munmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
# 32-bit off_t
addr = libc.mmap(None, SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, BASE)
os.close(fd)
if addr is None or addr == MAP_FAILED or addr == 0:
    sys.stderr.write("blank: libc mmap failed addr=%s\n" % addr)
    sys.exit(0)
buf = (ctypes.c_char * SIZE).from_address(addr)
ctypes.memset(addr, 0, SIZE)
libc.munmap(ctypes.c_void_p(addr), SIZE)
print("blanked 0x%08x %d bytes" % (BASE, SIZE))
PY
