/*
 * Copy the Xorg dummy root window into the WinEXE_Test FPGA framebuffer.
 *
 * Source: DISPLAY (default :0), 640x480, MIT-SHM GetImage.
 * Cursor: XFixes image composited into the SHM XImage (cached RAM), then
 *         one completed 640x480 BGRX memcpy into FPGA DDR. Do not blend
 *         the cursor into 0x30000000 after that copy (FPGA scans it live).
 *
 * Does not open /dev/fb0. Cross-compiled ARMv7; do not build on the SuperStation.
 *
 * Env:
 *   SS1_HZ        presentation pace (default 60). HDMI/Xorg stay 60 Hz.
 *   SS1_FRAME_US  >0 extra usleep after work; 0 = SS1_HZ pace; <0 = uncapped
 *   SS1_SKIP_UNCHANGED  1 = skip uncached DDR memcpy when composed frame
 *                       matches previous cached copy (default 1)
 *   SS1_DIRTY     1 = write only coarse dirty spans (needs skip + prev)
 *   SS1_TILE_W    dirty tile width in pixels (must divide 640; default 32)
 *   SS1_TILE_H    dirty tile height in pixels (must divide 480; default 32)
 *   SS1_DIRTY_PCT fallback to full memcpy if dirty coverage >= this % (default 60)
 *   SS1_XSYNC     1 = XSync after each frame (default 0; GetImage already waits)
 *   SS1_OSYNC     1 = O_SYNC /dev/mem (default 1). Non-RAM phys is uncached either way.
 *
 * Direct PAL8: if mailbox 0x30400000 magic=P8L8 and flags bit0, skip
 * XShmGetImage / memcmp / BGRX copy (C&C writes 0x30200000 itself).
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
#include <time.h>
#include <unistd.h>

#define FB_PHYS   0x30000000UL
#define FB_W      640
#define FB_H      480
#define FB_BPP    4
#define FB_STRIDE (FB_W * FB_BPP)
#define FB_SIZE   (FB_STRIDE * FB_H)
#define SS1_MBOX_PHYS     0x30400000UL
#define SS1_PAL8_MAGIC    0x50384C38u
#define SS1_PAL8_FLAG_EN  1u
#define PROFILE_EVERY 60
#define DIRTY_MAX_TX  64
#define DIRTY_MAX_TY  60
#define DIRTY_MAX_SPANS 48

static int ximage_direct_packed(const XImage *im)
{
	return im && im->data
		&& im->bits_per_pixel == 32 && im->byte_order == LSBFirst
		&& im->red_mask == 0x00ff0000UL
		&& im->green_mask == 0x0000ff00UL
		&& im->blue_mask == 0x000000ffUL
		&& im->width >= FB_W && im->height >= FB_H
		&& im->bytes_per_line == FB_STRIDE;
}

/* Sample 16 rows first so a changing map does not pay a full 1.2 MB memcmp
 * before the uncached DDR write. Full compare only if samples match (static
 * frame / cursor between sample rows). */
static int frame_changed(const char *cur, const char *old)
{
	int i;

	for (i = 0; i < 16; i++) {
		size_t off = (size_t)((i * (FB_H - 1)) / 15) * (size_t)FB_STRIDE;
		if (memcmp(cur + off, old + off, (size_t)FB_STRIDE) != 0)
			return 1;
	}
	return memcmp(cur, old, FB_SIZE) != 0;
}

static int tile_changed(const char *cur, const char *old, int tx, int ty, int tw, int th)
{
	int y;

	for (y = 0; y < th; y++) {
		size_t off = ((size_t)(ty + y) * (size_t)FB_W + (size_t)tx) * (size_t)FB_BPP;
		if (memcmp(cur + off, old + off, (size_t)tw * (size_t)FB_BPP) != 0)
			return 1;
	}
	return 0;
}

static void copy_rect(char *dst, const char *src, int x, int y, int w, int h)
{
	int row;

	if (x == 0 && w == FB_W) {
		memcpy(dst + (size_t)y * (size_t)FB_STRIDE,
		       src + (size_t)y * (size_t)FB_STRIDE,
		       (size_t)h * (size_t)FB_STRIDE);
		return;
	}
	for (row = 0; row < h; row++) {
		size_t off = ((size_t)(y + row) * (size_t)FB_W + (size_t)x) * (size_t)FB_BPP;
		memcpy(dst + off, src + off, (size_t)w * (size_t)FB_BPP);
	}
}

/*
 * Compare coarse tiles against prev (cached RAM). Coalesce adjacent dirty
 * tiles on the same tile-row into one horizontal span. If dirty coverage
 * hits thresh_pct, one full-frame DDR memcpy. Returns DDR bytes written.
 */
static size_t dirty_present(char *fb, const char *cur, char *prev,
			    int tile_w, int tile_h, int thresh_pct,
			    unsigned long *spans_out, unsigned long *pct_out,
			    unsigned long *fallback_out)
{
	uint64_t rowmask[DIRTY_MAX_TY];
	int nx = FB_W / tile_w;
	int ny = FB_H / tile_h;
	int ty, tx, spans = 0, fallback = 0;
	unsigned long dirty_tiles = 0, total_tiles = (unsigned long)nx * (unsigned long)ny;
	unsigned long dirty_px = 0, thresh_px, pct;
	size_t bytes = 0;

	thresh_px = ((unsigned long)FB_W * (unsigned long)FB_H * (unsigned long)thresh_pct) / 100ul;
	memset(rowmask, 0, sizeof rowmask);

	for (ty = 0; ty < ny; ty++) {
		for (tx = 0; tx < nx; tx++) {
			if (!tile_changed(cur, prev, tx * tile_w, ty * tile_h, tile_w, tile_h))
				continue;
			rowmask[ty] |= (1ull << tx);
			dirty_tiles++;
			dirty_px += (unsigned long)tile_w * (unsigned long)tile_h;
			if (dirty_px >= thresh_px) {
				fallback = 1;
				ty = ny;
				break;
			}
		}
	}

	pct = total_tiles ? (dirty_tiles * 100ul + total_tiles / 2ul) / total_tiles : 100ul;
	if (fallback)
		pct = (unsigned long)thresh_pct;

	if (fallback || dirty_px == 0) {
		if (fallback) {
			memcpy(fb, cur, FB_SIZE);
			bytes = FB_SIZE;
			spans = 1;
			memcpy(prev, cur, FB_SIZE);
		}
		if (spans_out)
			*spans_out = (unsigned long)spans;
		if (pct_out)
			*pct_out = pct;
		if (fallback_out)
			*fallback_out = (unsigned long)fallback;
		return bytes;
	}

	for (ty = 0; ty < ny; ty++) {
		tx = 0;
		while (tx < nx) {
			int run;

			if (!(rowmask[ty] & (1ull << tx))) {
				tx++;
				continue;
			}
			run = tx;
			while (run + 1 < nx && (rowmask[ty] & (1ull << (run + 1))))
				run++;
			if (spans >= DIRTY_MAX_SPANS) {
				memcpy(fb, cur, FB_SIZE);
				memcpy(prev, cur, FB_SIZE);
				if (spans_out)
					*spans_out = 1;
				if (pct_out)
					*pct_out = pct;
				if (fallback_out)
					*fallback_out = 1;
				return FB_SIZE;
			}
			copy_rect(fb, cur, tx * tile_w, ty * tile_h,
				  (run - tx + 1) * tile_w, tile_h);
			copy_rect(prev, cur, tx * tile_w, ty * tile_h,
				  (run - tx + 1) * tile_w, tile_h);
			bytes += (size_t)(run - tx + 1) * (size_t)tile_w
				* (size_t)tile_h * (size_t)FB_BPP;
			spans++;
			tx = run + 1;
		}
	}

	if (spans_out)
		*spans_out = (unsigned long)spans;
	if (pct_out)
		*pct_out = pct;
	if (fallback_out)
		*fallback_out = 0;
	return bytes;
}

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

static uint64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
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

	if (direct && w == FB_W && h == FB_H && im->bytes_per_line == FB_STRIDE) {
		memcpy(fb, im->data, FB_SIZE);
		return;
	}
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

/* Blend XFixes ARGB cursor into the cached SHM XImage. Next GetImage replaces it. */
static void blit_cursor(XImage *im, XFixesCursorImage *cur)
{
	int x0, y0, cx, cy, w, h;
	int direct;

	if (!im || !im->data || !cur)
		return;
	if (cur->width <= 0 || cur->height <= 0)
		return;
	w = im->width < FB_W ? im->width : FB_W;
	h = im->height < FB_H ? im->height : FB_H;
	if (w <= 0 || h <= 0)
		return;

	direct = (im->bits_per_pixel == 32 && im->byte_order == LSBFirst
		  && im->red_mask == 0x00ff0000UL
		  && im->green_mask == 0x0000ff00UL
		  && im->blue_mask == 0x000000ffUL
		  && im->bytes_per_line >= w * 4);

	x0 = (int)cur->x - (int)cur->xhot;
	y0 = (int)cur->y - (int)cur->yhot;
	for (cy = 0; cy < (int)cur->height; cy++) {
		int y = y0 + cy;
		char *row;
		if (y < 0 || y >= h)
			continue;
		row = im->data + (size_t)y * (size_t)im->bytes_per_line;
		for (cx = 0; cx < (int)cur->width; cx++) {
			unsigned long p;
			unsigned a, r, g, b;
			uint32_t dst, out;
			int x = x0 + cx;
			if (x < 0 || x >= w)
				continue;
			p = cur->pixels[(size_t)cy * (size_t)cur->width + (size_t)cx];
			a = (unsigned)((p >> 24) & 255ul);
			if (!a)
				continue;
			r = (unsigned)((p >> 16) & 255ul);
			g = (unsigned)((p >> 8) & 255ul);
			b = (unsigned)(p & 255ul);
			if (direct) {
				uint32_t *px = (uint32_t *)row + (size_t)x;
				dst = *px;
			} else {
				dst = pixel_from_ximage(im, x, y);
			}
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
			if (direct)
				*((uint32_t *)row + (size_t)x) = out;
			else
				XPutPixel(im, x, y, (unsigned long)out);
		}
	}
}

static long env_long(const char *name, long def)
{
	const char *s = getenv(name);
	char *end;
	long v;
	if (!s || !s[0])
		return def;
	v = strtol(s, &end, 10);
	if (end == s)
		return def;
	return v;
}

int main(int argc, char **argv)
{
	const char *display_name;
	Display *dpy;
	Window root;
	XImage *im;
	XShmSegmentInfo shm;
	uint32_t *fb;
	volatile uint32_t *mbox = NULL;
	int memfd, use_shm = 0, use_fixes = 0, ev_base = 0, err_base = 0;
	int pal8_idle = 0;
	int do_xsync, osync, skip_unchanged, dirty;
	int tile_w, tile_h, dirty_pct;
	unsigned long frames = 0, ddr_writes = 0, ddr_skips = 0;
	unsigned long acc_writes = 0, acc_skips = 0;
	unsigned long acc_ddr_bytes = 0, acc_spans = 0, acc_dirty_pct = 0, acc_fallback = 0;
	int once = 0, have_prev = 0;
	long frame_us, hz;
	uint64_t period_ns;
	uint32_t *prev = NULL;
	uint64_t acc_shm = 0, acc_ddr = 0, acc_cur_get = 0, acc_cur_blit = 0;
	uint64_t acc_cmp = 0, acc_xsync = 0, acc_sleep = 0, acc_total = 0;
	uint64_t t_loop0, deadline = 0;

	if (argc > 1 && !strcmp(argv[1], "once"))
		once = 1;

	frame_us = env_long("SS1_FRAME_US", 0);
	hz = env_long("SS1_HZ", 60);
	if (hz < 1)
		hz = 60;
	if (hz > 120)
		hz = 120;
	period_ns = 1000000000ull / (uint64_t)hz;
	skip_unchanged = (int)env_long("SS1_SKIP_UNCHANGED", 1);
	dirty = (int)env_long("SS1_DIRTY", 0);
	tile_w = (int)env_long("SS1_TILE_W", 32);
	tile_h = (int)env_long("SS1_TILE_H", 32);
	dirty_pct = (int)env_long("SS1_DIRTY_PCT", 60);
	if (tile_w < 8 || tile_h < 8 || FB_W % tile_w || FB_H % tile_h
	    || (FB_W / tile_w) > DIRTY_MAX_TX || (FB_H / tile_h) > DIRTY_MAX_TY)
		dirty = 0;
	if (dirty_pct < 10)
		dirty_pct = 10;
	if (dirty_pct > 95)
		dirty_pct = 95;
	do_xsync = (int)env_long("SS1_XSYNC", 0);

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
	printf("XShmGetImage drawable=0x%lx (DefaultRootWindow) %dx%d depth=%d — capture target unchanged\n",
	       (unsigned long)root,
	       DisplayWidth(dpy, DefaultScreen(dpy)),
	       DisplayHeight(dpy, DefaultScreen(dpy)),
	       DefaultDepth(dpy, DefaultScreen(dpy)));
	fflush(stdout);
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

	osync = (int)env_long("SS1_OSYNC", 1);
	memfd = open("/dev/mem", osync ? (O_RDWR | O_SYNC) : O_RDWR);
	if (memfd < 0) {
		perror("open /dev/mem");
		return 1;
	}
	fb = mmap(NULL, FB_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, (off_t)FB_PHYS);
	if (fb == MAP_FAILED) {
		perror("mmap 0x30000000");
		return 1;
	}
	mbox = mmap(NULL, 4096, PROT_READ, MAP_SHARED, memfd, (off_t)SS1_MBOX_PHYS);
	if (mbox == MAP_FAILED) {
		perror("mmap 0x30400000 mailbox");
		mbox = NULL;
	}
	if (skip_unchanged) {
		prev = malloc(FB_SIZE);
		if (!prev) {
			fprintf(stderr, "malloc prev frame failed; skip-unchanged disabled\n");
			skip_unchanged = 0;
		}
	}
	if (dirty && !skip_unchanged)
		dirty = 0;
	printf("WinEXE X11 presenter DISPLAY=%s shm=%d fixes=%d depth=%d bpp_guess=%d -> 0x%lx hz=%ld period_ns=%llu frame_us=%ld skip=%d dirty=%d tile=%dx%d pct=%d xsync=%d osync=%d\n",
	       display_name, use_shm, use_fixes,
	       DefaultDepth(dpy, DefaultScreen(dpy)),
	       im ? im->bits_per_pixel : 0, FB_PHYS, hz,
	       (unsigned long long)period_ns, frame_us, skip_unchanged,
	       dirty, tile_w, tile_h, dirty_pct, do_xsync, osync);
	if (im)
		printf("ximage bpp=%d bpl=%d byte_order=%d red=%lx green=%lx blue=%lx\n",
		       im->bits_per_pixel, im->bytes_per_line, im->byte_order,
		       im->red_mask, im->green_mask, im->blue_mask);
	fflush(stdout);

	t_loop0 = now_ns();
	for (;;) {
		XFixesCursorImage *cur = NULL;
		uint64_t t0, t_frame0 = now_ns();

		if (mbox && mbox[0] == SS1_PAL8_MAGIC && (mbox[1] & SS1_PAL8_FLAG_EN)) {
			if (!pal8_idle) {
				printf("pal8_idle: skip XShmGetImage/BGRX (presents=%u gen=%u)\n",
				       mbox[3], mbox[2]);
				fflush(stdout);
				pal8_idle = 1;
			}
			usleep(100000);
			continue;
		}
		if (pal8_idle) {
			printf("pal8_idle: mailbox clear, resume BGRX presenter\n");
			fflush(stdout);
			pal8_idle = 0;
			have_prev = 0;
		}

		if (use_shm) {
			t0 = now_ns();
			if (!XShmGetImage(dpy, root, im, 0, 0, AllPlanes)) {
				fprintf(stderr, "XShmGetImage failed\n");
				return 1;
			}
			acc_shm += now_ns() - t0;
			if (use_fixes) {
				t0 = now_ns();
				cur = XFixesGetCursorImage(dpy);
				acc_cur_get += now_ns() - t0;
				if (cur) {
					if (frames == 0)
						printf("cursor %dx%d hot=%d,%d pos=%d,%d\n",
						       (int)cur->width, (int)cur->height,
						       (int)cur->xhot, (int)cur->yhot,
						       (int)cur->x, (int)cur->y);
					t0 = now_ns();
					blit_cursor(im, cur);
					acc_cur_blit += now_ns() - t0;
					XFree(cur);
					cur = NULL;
				}
			}
			t0 = now_ns();
			if (skip_unchanged && prev && ximage_direct_packed(im)) {
				int changed = !have_prev || frame_changed(im->data, (const char *)prev);
				acc_cmp += now_ns() - t0;
				if (changed) {
					unsigned long span_n = 1, d_pct = 100, fb_full = 1;
					size_t wrote;

					t0 = now_ns();
					if (dirty && have_prev) {
						wrote = dirty_present((char *)fb, im->data, (char *)prev,
								      tile_w, tile_h, dirty_pct,
								      &span_n, &d_pct, &fb_full);
					} else {
						memcpy(fb, im->data, FB_SIZE);
						wrote = FB_SIZE;
						memcpy(prev, im->data, FB_SIZE);
					}
					acc_ddr += now_ns() - t0;
					have_prev = 1;
					ddr_writes++;
					acc_writes++;
					acc_ddr_bytes += wrote;
					acc_spans += span_n;
					acc_dirty_pct += d_pct;
					acc_fallback += fb_full;
				} else {
					ddr_skips++;
					acc_skips++;
				}
			} else {
				blit_image(fb, im);
				acc_ddr += now_ns() - t0;
				ddr_writes++;
				acc_writes++;
				acc_ddr_bytes += FB_SIZE;
				acc_spans++;
				acc_dirty_pct += 100;
				acc_fallback++;
			}
		} else {
			XImage *tmp;
			t0 = now_ns();
			tmp = XGetImage(dpy, root, 0, 0, FB_W, FB_H, AllPlanes, ZPixmap);
			acc_shm += now_ns() - t0;
			if (!tmp) {
				fprintf(stderr, "XGetImage failed\n");
				return 1;
			}
			if (frames == 0)
				printf("XGetImage bpp=%d red=%lx green=%lx blue=%lx\n",
				       tmp->bits_per_pixel, tmp->red_mask, tmp->green_mask, tmp->blue_mask);
			if (use_fixes) {
				t0 = now_ns();
				cur = XFixesGetCursorImage(dpy);
				acc_cur_get += now_ns() - t0;
				if (cur) {
					t0 = now_ns();
					blit_cursor(tmp, cur);
					acc_cur_blit += now_ns() - t0;
					XFree(cur);
					cur = NULL;
				}
			}
			t0 = now_ns();
			blit_image(fb, tmp);
			acc_ddr += now_ns() - t0;
			ddr_writes++;
			acc_writes++;
			XDestroyImage(tmp);
		}
		if (do_xsync) {
			t0 = now_ns();
			XSync(dpy, False);
			acc_xsync += now_ns() - t0;
		}
		frames++;
		acc_total += now_ns() - t_frame0;
		if (frames == 1 || (frames % PROFILE_EVERY) == 0) {
			double n = (double)(frames % PROFILE_EVERY == 0 ? PROFILE_EVERY : frames);
			double wall_ms = (double)(now_ns() - t_loop0) / 1e6;
			double fps = (wall_ms > 0.0) ? (n * 1000.0 / wall_ms) : 0.0;
			printf("frames=%lu shm=%.2f ddr=%.2f cmp=%.2f cur_get=%.2f cur_blit=%.2f xsync=%.2f sleep=%.2f work=%.2f fps=%.1f ddr_hz=%.1f skip=%lu write=%lu dirty_pct=%.0f spans=%.1f ddr_kBps=%.0f fallback=%lu (ms/frame, last %g)\n",
			       frames,
			       (double)acc_shm / n / 1e6,
			       (double)acc_ddr / n / 1e6,
			       (double)acc_cmp / n / 1e6,
			       (double)acc_cur_get / n / 1e6,
			       (double)acc_cur_blit / n / 1e6,
			       (double)acc_xsync / n / 1e6,
			       (double)acc_sleep / n / 1e6,
			       (double)acc_total / n / 1e6,
			       fps,
			       wall_ms > 0.0 ? (acc_writes * 1000.0 / wall_ms) : 0.0,
			       acc_skips, acc_writes,
			       acc_writes ? (double)acc_dirty_pct / (double)acc_writes : 0.0,
			       acc_writes ? (double)acc_spans / (double)acc_writes : 0.0,
			       wall_ms > 0.0 ? ((double)acc_ddr_bytes / 1024.0) * (1000.0 / wall_ms) : 0.0,
			       acc_fallback, n);
			fflush(stdout);
			acc_shm = acc_ddr = acc_cur_get = acc_cur_blit = 0;
			acc_cmp = acc_xsync = acc_sleep = acc_total = 0;
			acc_writes = acc_skips = 0;
			acc_ddr_bytes = acc_spans = acc_dirty_pct = acc_fallback = 0;
			t_loop0 = now_ns();
		}
		if (once)
			break;
		if (frame_us > 0) {
			t0 = now_ns();
			usleep((useconds_t)frame_us);
			acc_sleep += now_ns() - t0;
		} else if (frame_us == 0) {
			struct timespec ts;
			t0 = now_ns();
			if (deadline == 0)
				deadline = t0;
			deadline += period_ns;
			if (deadline + period_ns < t0)
				deadline = t0; /* fell more than one tick behind */
			if (deadline > t0) {
				ts.tv_sec = (time_t)(deadline / 1000000000ull);
				ts.tv_nsec = (long)(deadline % 1000000000ull);
				clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL);
			}
			acc_sleep += now_ns() - t0;
		}
	}

	free(prev);
	munmap(fb, FB_SIZE);
	if (mbox && mbox != MAP_FAILED)
		munmap((void *)mbox, 4096);
	close(memfd);
	if (use_shm) {
		XShmDetach(dpy, &shm);
		shmdt(shm.shmaddr);
		XDestroyImage(im);
	}
	XCloseDisplay(dpy);
	return 0;
}
