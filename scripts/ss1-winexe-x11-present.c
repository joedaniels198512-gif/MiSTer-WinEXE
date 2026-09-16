/*
 * Copy the Xorg dummy root window into the WinEXE_Test FPGA framebuffer.
 *
 * Source: DISPLAY (default :0), 640x480, MIT-SHM GetImage + XFixes cursor.
 * Dest:   /dev/mem 0x30000000, 640x480 packed BGRX, stride 2560.
 *
 * Does not open /dev/fb0. Cross-compiled ARMv7; do not build on the SuperStation.
 */
#define _GNU_SOURCE
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XShm.h>
#include <X11/extensions/Xfixes.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/shm.h>
#include <unistd.h>

#define FB_PHYS   0x30000000UL
#define FB_W      640
#define FB_H      480
#define FB_BPP    4
#define FB_STRIDE (FB_W * FB_BPP)
#define FB_SIZE   (FB_STRIDE * FB_H)
#define FRAME_US  50000

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

static uint32_t pack_bgrx(unsigned r, unsigned g, unsigned b)
{
	return (uint32_t)(b & 255u) | ((uint32_t)(g & 255u) << 8) | ((uint32_t)(r & 255u) << 16);
}

static uint32_t pixel_from_ximage(XImage *im, int x, int y)
{
	unsigned long p = XGetPixel(im, x, y);
	unsigned r, g, b;
	unsigned rm = im->red_mask, gm = im->green_mask, bm = im->blue_mask;
	unsigned rs = 0, gs = 0, bs = 0;

	if (!rm || !gm || !bm)
		return pack_bgrx((p >> 16) & 255u, (p >> 8) & 255u, p & 255u);

	while (rm && (rm & 1u) == 0) { rm >>= 1; rs++; }
	while (gm && (gm & 1u) == 0) { gm >>= 1; gs++; }
	while (bm && (bm & 1u) == 0) { bm >>= 1; bs++; }
	r = (unsigned)((p >> rs) & rm);
	g = (unsigned)((p >> gs) & gm);
	b = (unsigned)((p >> bs) & bm);
	if (rm > 255u) r = r * 255u / rm;
	if (gm > 255u) g = g * 255u / gm;
	if (bm > 255u) b = b * 255u / bm;
	return pack_bgrx(r, g, b);
}

static void blit_image(uint32_t *fb, XImage *im)
{
	int x, y;
	int w = im->width < FB_W ? im->width : FB_W;
	int h = im->height < FB_H ? im->height : FB_H;
	int direct = (im->bits_per_pixel == 32 && im->byte_order == LSBFirst
		      && im->red_mask == 0x00ff0000UL
		      && im->green_mask == 0x0000ff00UL
		      && im->blue_mask == 0x000000ffUL);

	if (direct) {
		for (y = 0; y < h; y++) {
			memcpy(fb + (size_t)y * FB_W,
			       im->data + (size_t)y * (size_t)im->bytes_per_line,
			       (size_t)w * 4u);
			for (x = w; x < FB_W; x++)
				fb[(size_t)y * FB_W + (size_t)x] = 0;
		}
	} else {
		for (y = 0; y < h; y++) {
			for (x = 0; x < w; x++)
				fb[(size_t)y * FB_W + (size_t)x] = pixel_from_ximage(im, x, y);
			for (x = w; x < FB_W; x++)
				fb[(size_t)y * FB_W + (size_t)x] = 0;
		}
	}
	for (y = h; y < FB_H; y++)
		memset(fb + (size_t)y * FB_W, 0, FB_STRIDE);
}

static void blit_cursor(uint32_t *fb, XFixesCursorImage *cur)
{
	int x0, y0, cx, cy;
	if (!cur || cur->width <= 0 || cur->height <= 0)
		return;
	x0 = (int)cur->x - (int)cur->xhot;
	y0 = (int)cur->y - (int)cur->yhot;
	for (cy = 0; cy < (int)cur->height; cy++) {
		int y = y0 + cy;
		if (y < 0 || y >= FB_H)
			continue;
		for (cx = 0; cx < (int)cur->width; cx++) {
			unsigned long p;
			unsigned a, r, g, b;
			uint32_t dst, out;
			int x = x0 + cx;
			if (x < 0 || x >= FB_W)
				continue;
			p = cur->pixels[(size_t)cy * (size_t)cur->width + (size_t)cx];
			a = (unsigned)((p >> 24) & 255ul);
			if (!a)
				continue;
			r = (unsigned)((p >> 16) & 255ul);
			g = (unsigned)((p >> 8) & 255ul);
			b = (unsigned)(p & 255ul);
			dst = fb[(size_t)y * FB_W + (size_t)x];
			if (a == 255u) {
				out = pack_bgrx(r, g, b);
			} else {
				unsigned db = dst & 255u;
				unsigned dg = (dst >> 8) & 255u;
				unsigned dr = (dst >> 16) & 255u;
				unsigned ia = 255u - a;
				out = pack_bgrx((r * a + dr * ia) / 255u,
						(g * a + dg * ia) / 255u,
						(b * a + db * ia) / 255u);
			}
			fb[(size_t)y * FB_W + (size_t)x] = out;
		}
	}
}

int main(int argc, char **argv)
{
	const char *display_name;
	Display *dpy;
	Window root;
	XImage *im;
	XShmSegmentInfo shm;
	uint32_t *fb;
	int memfd, use_shm = 0, use_fixes = 0, ev_base = 0, err_base = 0;
	unsigned long frames = 0;
	int once = 0;

	if (argc > 1 && !strcmp(argv[1], "once"))
		once = 1;

	display_name = getenv("DISPLAY");
	if (!display_name || !display_name[0])
		display_name = ":0";

	if (overlaps_system_ram(FB_PHYS, FB_SIZE) == 1) {
		fprintf(stderr, "refusing: 0x%lx overlaps System RAM\n", FB_PHYS);
		return 1;
	}

	dpy = XOpenDisplay(display_name);
	if (!dpy) {
		fprintf(stderr, "XOpenDisplay(%s) failed\n", display_name);
		return 1;
	}
	root = DefaultRootWindow(dpy);
	if (DisplayWidth(dpy, DefaultScreen(dpy)) != FB_W
	    || DisplayHeight(dpy, DefaultScreen(dpy)) != FB_H) {
		fprintf(stderr, "warning: X size %dx%d, FPGA FB is %dx%d\n",
			DisplayWidth(dpy, DefaultScreen(dpy)),
			DisplayHeight(dpy, DefaultScreen(dpy)), FB_W, FB_H);
	}

	memset(&shm, 0, sizeof shm);
	im = NULL;
	if (XShmQueryExtension(dpy)) {
		im = XShmCreateImage(dpy, DefaultVisual(dpy, DefaultScreen(dpy)),
				     (unsigned)DefaultDepth(dpy, DefaultScreen(dpy)),
				     ZPixmap, NULL, &shm, FB_W, FB_H);
		if (im) {
			shm.shmid = shmget(IPC_PRIVATE, (size_t)(im->bytes_per_line * im->height),
					   IPC_CREAT | 0600);
			if (shm.shmid >= 0) {
				shm.shmaddr = shmat(shm.shmid, 0, 0);
				if (shm.shmaddr != (char *)-1) {
					im->data = shm.shmaddr;
					shm.readOnly = False;
					if (XShmAttach(dpy, &shm)) {
						use_shm = 1;
						shmctl(shm.shmid, IPC_RMID, 0);
					}
				}
			}
			if (!use_shm) {
				if (im->data && shm.shmaddr && shm.shmaddr != (char *)-1)
					shmdt(shm.shmaddr);
				XDestroyImage(im);
				im = NULL;
			}
		}
	}

	use_fixes = XFixesQueryExtension(dpy, &ev_base, &err_base);

	memfd = open("/dev/mem", O_RDWR | O_SYNC);
	if (memfd < 0) {
		perror("open /dev/mem");
		return 1;
	}
	fb = mmap(NULL, FB_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, (off_t)FB_PHYS);
	if (fb == MAP_FAILED) {
		perror("mmap 0x30000000");
		return 1;
	}

	printf("WinEXE X11 presenter DISPLAY=%s shm=%d fixes=%d depth=%d bpp_guess=%d -> 0x%lx\n",
	       display_name, use_shm, use_fixes,
	       DefaultDepth(dpy, DefaultScreen(dpy)),
	       im ? im->bits_per_pixel : 0, FB_PHYS);
	fflush(stdout);

	for (;;) {
		XFixesCursorImage *cur = NULL;
		if (use_shm) {
			if (!XShmGetImage(dpy, root, im, 0, 0, AllPlanes)) {
				fprintf(stderr, "XShmGetImage failed\n");
				return 1;
			}
			blit_image(fb, im);
		} else {
			XImage *tmp = XGetImage(dpy, root, 0, 0, FB_W, FB_H, AllPlanes, ZPixmap);
			if (!tmp) {
				fprintf(stderr, "XGetImage failed\n");
				return 1;
			}
			if (frames == 0)
				printf("XGetImage bpp=%d red=%lx green=%lx blue=%lx\n",
				       tmp->bits_per_pixel, tmp->red_mask, tmp->green_mask, tmp->blue_mask);
			blit_image(fb, tmp);
			XDestroyImage(tmp);
		}
		if (use_fixes) {
			cur = XFixesGetCursorImage(dpy);
			if (cur) {
				blit_cursor(fb, cur);
				XFree(cur);
			}
		}
		XSync(dpy, False);
		frames++;
		if (frames == 1 || (frames % 60) == 0) {
			printf("frames=%lu shm=%d\n", frames, use_shm);
			fflush(stdout);
		}
		if (once)
			break;
		usleep(FRAME_US);
	}

	munmap(fb, FB_SIZE);
	close(memfd);
	if (use_shm) {
		XShmDetach(dpy, &shm);
		shmdt(shm.shmaddr);
		XDestroyImage(im);
	}
	XCloseDisplay(dpy);
	return 0;
}
