/*
 * In-process Direct PAL8 present hook for Wine 7.1 ddraw.
 *
 * Preferred site: ddraw_surface_update_frontbuffer (cdecl).
 * Found by intersecting CALL targets of IDirectDrawSurface Blt / Flip /
 * SetPalette (all call that helper). On a qualifying 640×480 P8 primary
 * present (read==0): copy 307 200 indexed bytes + palette into FPGA DDR
 * and return DD_OK so GDI BitBlt / winex11 XShmPutImage are skipped.
 *
 * Eligibility fail or read!=0 → original Wine/X path.
 *
 * i686-w64-mingw32-gcc -O2 -Wall -shared -o ss1-cnc-pal8.dll \
 *     ss1-cnc-pal8-hook.c -static-libgcc
 *
 * Does not patch C&C95.EXE on disk. Does not hook Lock/Unlock.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ddraw.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ss1-pal8.h"

#define DDS1_OFF           16
#define VT_BLT             5
#define VT_FLIP            11
#define VT_GETPALETTE      20
#define VT_GETSURFACEDESC  22
#define VT_LOCK            25
#define VT_SETPALETTE      31
#define VT_UNLOCK          32
#define PAL_VT_GETENTRIES  4

typedef HRESULT (__cdecl *update_fb_fn)(void *surface, const RECT *rect,
                                        BOOL read, unsigned swap);

static update_fb_fn g_orig;
static uint8_t g_stolen[16];
static size_t g_stolen_n;
static uint8_t *g_site;
static uint8_t *g_tramp;
static int g_ready;
static uint32_t g_last_pal[256];
static int g_have_pal;
static FILE *g_log;

static void flog(const char *fmt, ...)
{
	va_list ap;
	if (!g_log)
		return;
	va_start(ap, fmt);
	vfprintf(g_log, fmt, ap);
	va_end(ap);
	fputc('\n', g_log);
	fflush(g_log);
}

static uint64_t qpc_ns(void)
{
	static LARGE_INTEGER freq;
	LARGE_INTEGER t;
	if (!freq.QuadPart)
		QueryPerformanceFrequency(&freq);
	QueryPerformanceCounter(&t);
	if (!freq.QuadPart)
		return 0;
	return (uint64_t)t.QuadPart * 1000000000ull / (uint64_t)freq.QuadPart;
}

static int collect_calls(const uint8_t *fn, size_t maxn,
                         uint32_t *out, int max_out, uint32_t lo, uint32_t hi)
{
	size_t i;
	int n = 0;
	for (i = 0; i + 5 <= maxn && n < max_out; i++) {
		if (fn[i] == 0xE8) {
			int32_t rel;
			uint32_t tgt;
			memcpy(&rel, fn + i + 1, 4);
			tgt = (uint32_t)(fn + i + 5) + (uint32_t)rel;
			if (tgt >= lo && tgt < hi)
				out[n++] = tgt;
		}
	}
	return n;
}

static int in_list(const uint32_t *a, int na, uint32_t v)
{
	int i;
	for (i = 0; i < na; i++)
		if (a[i] == v)
			return 1;
	return 0;
}

static uint32_t find_update_frontbuffer(void)
{
	IDirectDrawSurface *prim;
	void **vtbl;
	uint32_t ddraw_lo = 0, ddraw_hi = 0;
	MEMORY_BASIC_INFORMATION mbi;
	uint32_t blt_c[32], flip_c[32], pal_c[32];
	int nb, nf, np, i;
	HMODULE ddraw;

	prim = *(IDirectDrawSurface **)(uintptr_t)0x541AEC;
	if (!prim)
		return 0;
	vtbl = *(void ***)prim;
	if (!vtbl)
		return 0;

	ddraw = GetModuleHandleA("ddraw.dll");
	if (!ddraw)
		return 0;
	if (!VirtualQuery(ddraw, &mbi, sizeof mbi))
		return 0;
	ddraw_lo = (uint32_t)(uintptr_t)mbi.AllocationBase;
	{
		uint32_t p = ddraw_lo;
		while (VirtualQuery((void *)(uintptr_t)p, &mbi, sizeof mbi) &&
		       (uint32_t)(uintptr_t)mbi.AllocationBase == ddraw_lo) {
			p += (uint32_t)mbi.RegionSize;
			if (p < ddraw_lo)
				break;
		}
		ddraw_hi = p;
	}

	nb = collect_calls((const uint8_t *)vtbl[VT_BLT], 2048, blt_c, 32, ddraw_lo, ddraw_hi);
	nf = collect_calls((const uint8_t *)vtbl[VT_FLIP], 1024, flip_c, 32, ddraw_lo, ddraw_hi);
	np = collect_calls((const uint8_t *)vtbl[VT_SETPALETTE], 1024, pal_c, 32, ddraw_lo, ddraw_hi);

	for (i = 0; i < nb; i++) {
		if (in_list(flip_c, nf, blt_c[i]) && in_list(pal_c, np, blt_c[i]))
			return blt_c[i];
	}
	/* Blt + SetPalette is enough if Flip is unused. */
	for (i = 0; i < nb; i++) {
		if (in_list(pal_c, np, blt_c[i]))
			return blt_c[i];
	}
	return 0;
}

static size_t steal_len(const uint8_t *p)
{
	if (p[0] == 0x55 && p[1] == 0x8B && p[2] == 0xEC && p[3] == 0x83 && p[4] == 0xEC)
		return 6;
	if (p[0] == 0x55 && p[1] == 0x89 && p[2] == 0xE5 && p[3] == 0x83 && p[4] == 0xEC)
		return 6;
	if (p[0] == 0x55 && p[1] == 0x8B && p[2] == 0xEC && p[3] == 0x81 && p[4] == 0xEC)
		return 9;
	return 5;
}

static void copy_pal8(const uint8_t *src, int pitch)
{
	uint8_t *dst = (uint8_t *)(uintptr_t)SS1_PAL8_PHYS;
	int y;
	if (pitch == SS1_PAL8_STRIDE) {
		memcpy(dst, src, SS1_PAL8_SIZE);
		return;
	}
	for (y = 0; y < SS1_PAL8_H; y++)
		memcpy(dst + (size_t)y * SS1_PAL8_STRIDE, src + (size_t)y * (size_t)pitch,
		       SS1_PAL8_W);
}

static void note_copy(uint64_t ns)
{
	volatile uint32_t *st = (volatile uint32_t *)(uintptr_t)SS1_PAL8_STATS_PHYS;
	volatile uint32_t *mb = (volatile uint32_t *)(uintptr_t)SS1_MBOX_PHYS;
	uint64_t sum, bytes;
	uint32_t i;

	st[SS1_STAT_COPIES / 4] += 1;
	sum = (uint64_t)st[SS1_STAT_COPY_NS_SUM / 4] |
	      ((uint64_t)st[SS1_STAT_COPY_NS_SUM / 4 + 1] << 32);
	sum += ns;
	st[SS1_STAT_COPY_NS_SUM / 4] = (uint32_t)sum;
	st[SS1_STAT_COPY_NS_SUM / 4 + 1] = (uint32_t)(sum >> 32);
	if ((uint32_t)ns > st[SS1_STAT_COPY_NS_MAX / 4])
		st[SS1_STAT_COPY_NS_MAX / 4] = (uint32_t)ns;
	bytes = (uint64_t)st[SS1_STAT_BYTES / 4] |
	        ((uint64_t)st[SS1_STAT_BYTES / 4 + 1] << 32);
	bytes += SS1_PAL8_SIZE;
	st[SS1_STAT_BYTES / 4] = (uint32_t)bytes;
	st[SS1_STAT_BYTES / 4 + 1] = (uint32_t)(bytes >> 32);
	i = st[SS1_STAT_RING_I / 4] % SS1_STAT_RING_N;
	st[(SS1_STAT_RING / 4) + i] = (uint32_t)ns;
	st[SS1_STAT_RING_I / 4] = i + 1;
	mb[SS1_MBOX_OFF_PRESENTS / 4] += 1;
	st[SS1_STAT_PRESENTS / 4] = mb[SS1_MBOX_OFF_PRESENTS / 4];
}

static void maybe_palette(IDirectDrawSurface *iface)
{
	IDirectDrawPalette *pal = NULL;
	PALETTEENTRY ent[256];
	uint32_t packed[256];
	HRESULT (__stdcall *GetPalette)(IDirectDrawSurface *, IDirectDrawPalette **);
	HRESULT (__stdcall *GetEntries)(IDirectDrawPalette *, DWORD, DWORD, DWORD, PALETTEENTRY *);
	void **pvt;
	int i, changed = 0;
	volatile uint32_t *dst;
	volatile uint32_t *mb;

	GetPalette = ((void ***)iface)[0][VT_GETPALETTE];
	if (GetPalette(iface, &pal) || !pal)
		return;
	pvt = *(void ***)pal;
	GetEntries = pvt[PAL_VT_GETENTRIES];
	if (GetEntries(pal, 0, 0, 256, ent) == DD_OK) {
		for (i = 0; i < 256; i++)
			packed[i] = ((uint32_t)ent[i].peRed << 16) |
			            ((uint32_t)ent[i].peGreen << 8) |
			            (uint32_t)ent[i].peBlue;
		if (!g_have_pal || memcmp(packed, g_last_pal, sizeof packed) != 0) {
			changed = 1;
			memcpy(g_last_pal, packed, sizeof packed);
			g_have_pal = 1;
		}
	}
	pal->lpVtbl->Release(pal);
	if (!changed)
		return;
	dst = (volatile uint32_t *)(uintptr_t)SS1_PAL8_PAL_PHYS;
	for (i = 0; i < 256; i++)
		dst[i] = packed[i];
	mb = (volatile uint32_t *)(uintptr_t)SS1_MBOX_PHYS;
	mb[SS1_MBOX_OFF_PAL_GEN / 4] += 1;
}

static int eligible(IDirectDrawSurface *iface)
{
	DDSURFACEDESC ddsd;
	HRESULT (__stdcall *GetDesc)(IDirectDrawSurface *, DDSURFACEDESC *);

	memset(&ddsd, 0, sizeof ddsd);
	ddsd.dwSize = sizeof ddsd;
	GetDesc = ((void ***)iface)[0][VT_GETSURFACEDESC];
	if (GetDesc(iface, &ddsd) != DD_OK)
		return 0;
	if (!(ddsd.ddsCaps.dwCaps & DDSCAPS_PRIMARYSURFACE))
		return 0;
	if (ddsd.dwWidth != SS1_PAL8_W || ddsd.dwHeight != SS1_PAL8_H)
		return 0;
	if (!(ddsd.ddpfPixelFormat.dwFlags & DDPF_PALETTEINDEXED8) &&
	    ddsd.ddpfPixelFormat.dwRGBBitCount != 8)
		return 0;
	return 1;
}

static HRESULT __cdecl hook_update_fb(void *surface, const RECT *rect,
                                      BOOL read, unsigned swap)
{
	IDirectDrawSurface *iface;
	DDSURFACEDESC lock;
	HRESULT (__stdcall *Lock)(IDirectDrawSurface *, LPRECT, DDSURFACEDESC *, DWORD, HANDLE);
	HRESULT (__stdcall *Unlock)(IDirectDrawSurface *, LPVOID);
	volatile uint32_t *mb;
	uint64_t t0, dt;

	if (read || !surface || !g_orig)
		return g_orig(surface, rect, read, swap);

	mb = (volatile uint32_t *)(uintptr_t)SS1_MBOX_PHYS;
	if (mb[SS1_MBOX_OFF_MAGIC / 4] != SS1_PAL8_MAGIC)
		return g_orig(surface, rect, read, swap);

	iface = (IDirectDrawSurface *)((char *)surface + DDS1_OFF);
	if (!eligible(iface))
		return g_orig(surface, rect, read, swap);

	memset(&lock, 0, sizeof lock);
	lock.dwSize = sizeof lock;
	Lock = ((void ***)iface)[0][VT_LOCK];
	Unlock = ((void ***)iface)[0][VT_UNLOCK];
	if (Lock(iface, NULL, &lock, DDLOCK_WAIT | DDLOCK_READONLY, NULL) != DD_OK)
		return g_orig(surface, rect, read, swap);
	if (!lock.lpSurface) {
		Unlock(iface, NULL);
		return g_orig(surface, rect, read, swap);
	}

	t0 = qpc_ns();
	copy_pal8((const uint8_t *)lock.lpSurface, (int)lock.lPitch);
	dt = qpc_ns() - t0;
	Unlock(iface, NULL);

	maybe_palette(iface);
	mb[SS1_MBOX_OFF_FLAGS / 4] = SS1_PAL8_FLAG_EN;
	note_copy(dt);
	return DD_OK;
}

static int plant(uint32_t site)
{
	DWORD old = 0;
	uint8_t jmp[16];
	int32_t rel;
	size_t n;

	g_site = (uint8_t *)(uintptr_t)site;
	n = steal_len(g_site);
	if (n < 5 || n > sizeof g_stolen)
		return 0;
	g_stolen_n = n;
	memcpy(g_stolen, g_site, n);

	g_tramp = VirtualAlloc(NULL, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
	if (!g_tramp)
		return 0;
	memcpy(g_tramp, g_stolen, n);
	g_tramp[n] = 0xE9;
	rel = (int32_t)((g_site + n) - (g_tramp + n + 5));
	memcpy(g_tramp + n + 1, &rel, 4);
	g_orig = (update_fb_fn)g_tramp;

	memset(jmp, 0x90, sizeof jmp);
	jmp[0] = 0xE9;
	rel = (int32_t)((uint8_t *)&hook_update_fb - (g_site + 5));
	memcpy(jmp + 1, &rel, 4);
	if (!VirtualProtect(g_site, n, PAGE_EXECUTE_READWRITE, &old))
		return 0;
	memcpy(g_site, jmp, n);
	VirtualProtect(g_site, n, old, &old);
	FlushInstructionCache(GetCurrentProcess(), g_site, n);
	return 1;
}

static DWORD WINAPI boot(LPVOID arg)
{
	DWORD t0 = GetTickCount();
	uint32_t site = 0;
	(void)arg;
	g_log = fopen("Z:\\tmp\\ss1-cnc-pal8.log", "w");
	if (g_log)
		setvbuf(g_log, NULL, _IONBF, 0);
	flog("pal8 hook dll pid=%lu", (unsigned long)GetCurrentProcessId());

	while (GetTickCount() - t0 < 30000) {
		IDirectDrawSurface *prim = *(IDirectDrawSurface **)(uintptr_t)0x541AEC;
		if (prim && GetModuleHandleA("ddraw.dll")) {
			site = find_update_frontbuffer();
			if (site)
				break;
		}
		Sleep(50);
	}
	if (!site) {
		flog("update_frontbuffer not found; Wine/X path remains");
		return 1;
	}
	flog("update_frontbuffer=0x%lx", (unsigned long)site);
	if (!plant(site)) {
		flog("plant failed");
		return 1;
	}
	g_ready = 1;
	flog("planted; PAL8 copy on qualifying present, else Wine/X");
	flog("cursor: C&C software cursor is expected in the 8-bit surface (Test B)");
	return 0;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID res)
{
	(void)res;
	if (reason == DLL_PROCESS_ATTACH) {
		DisableThreadLibraryCalls(inst);
		CreateThread(NULL, 0, boot, NULL, 0, NULL);
	}
	return TRUE;
}
