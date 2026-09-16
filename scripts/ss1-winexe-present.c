/*
 * Write a 640x480 BGRX test pattern into the WinEXE_Test FPGA framebuffer.
 * Physical base: 0x30000000 (outside Linux 511 MB; same window DVD used).
 *
 * Usage: ss1-winexe-present [pattern]
 * Cross-compiled ARMv7; do not build on the SuperStation.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define FB_PHYS   0x30000000UL
#define FB_W      640
#define FB_H      480
#define FB_BPP    4
#define FB_STRIDE (FB_W * FB_BPP)
#define FB_SIZE   (FB_STRIDE * FB_H)

/* BGRX little-endian: byte0=B, byte1=G, byte2=R, byte3=X */
#define PX(r, g, b) ((uint32_t)(b) | ((uint32_t)(g) << 8) | ((uint32_t)(r) << 16))

static int overlaps_system_ram(unsigned long base, unsigned long size)
{
	FILE *f = fopen("/proc/iomem", "r");
	char line[256];
	int hit = 0;
	if (!f)
		return -1;
	while (fgets(line, sizeof line, f)) {
		unsigned long a, b;
		if (!strstr(line, "System RAM"))
			continue;
		if (sscanf(line, "%lx-%lx", &a, &b) != 2)
			continue;
		b += 1;
		if (base < b && base + size > a)
			hit = 1;
	}
	fclose(f);
	return hit;
}

int main(void)
{
	int fd;
	uint32_t *fb;
	unsigned x, y;
	static const uint32_t bars[8] = {
		PX(255, 255, 255), /* white */
		PX(255, 255,   0), /* yellow */
		PX(  0, 255, 255), /* cyan */
		PX(  0, 255,   0), /* green */
		PX(255,   0, 255), /* magenta */
		PX(255,   0,   0), /* red */
		PX(  0,   0, 255), /* blue */
		PX(  0,   0,   0)  /* black */
	};

	if (overlaps_system_ram(FB_PHYS, FB_SIZE) == 1) {
		fprintf(stderr, "refusing: 0x%lx overlaps System RAM\n", FB_PHYS);
		return 1;
	}

	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) {
		perror("open /dev/mem");
		return 1;
	}
	fb = mmap(NULL, FB_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)FB_PHYS);
	if (fb == MAP_FAILED) {
		perror("mmap");
		return 1;
	}

	for (y = 0; y < FB_H; y++) {
		for (x = 0; x < FB_W; x++) {
			uint32_t c;
			if (y < 360)
				c = bars[x / 80];
			else {
				unsigned cx = (x / 16) & 1u;
				unsigned cy = (y / 16) & 1u;
				c = (cx ^ cy) ? PX(255, 255, 255) : PX(0, 0, 0);
			}
			fb[y * FB_W + x] = c;
		}
	}

	printf("WinEXE pattern 640x480 BGRX stride=%u at 0x%lx (%u bytes)\n",
	       FB_STRIDE, FB_PHYS, (unsigned)FB_SIZE);
	printf("top: 8 colour bars  bottom: 16px checkerboard\n");
	munmap(fb, FB_SIZE);
	close(fd);
	return 0;
}
