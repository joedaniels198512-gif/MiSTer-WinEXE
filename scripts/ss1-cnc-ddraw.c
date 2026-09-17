/*
 * Tiny PE32 DirectDraw probe: reproduce stock C&C95 Gold's Wine-observed sequence.
 * Does not launch or patch C&C. Logs numeric + symbolic HRESULTs.
 *
 * i686-w64-mingw32-gcc -O2 -Wall -s -o ss1-cnc-ddraw.exe ss1-cnc-ddraw.c \
 *     -static-libgcc -lddraw -lgdi32 -luser32
 */
#define WIN32_LEAN_AND_MEAN
#define INITGUID
#include <windows.h>
#include <ddraw.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

static FILE *g_log;
static DWORD g_t0;

static const char *hr_name(HRESULT hr)
{
    switch ((unsigned long)hr) {
    case 0x00000000UL: return "DD_OK";
    case 0x00000001UL: return "S_FALSE";
    case 0x80004005UL: return "E_FAIL";
    case 0x80004001UL: return "E_NOTIMPL";
    case 0x8007000EUL: return "E_OUTOFMEMORY";
    case 0x80070057UL: return "E_INVALIDARG";
    case 0x80040154UL: return "REGDB_E_CLASSNOTREG";
    case 0x88760005UL: return "DDERR_ALREADYINITIALIZED";
    case 0x8876000AUL: return "DDERR_CANNOTATTACHSURFACE";
    case 0x88760014UL: return "DDERR_CANNOTDETACHSURFACE";
    case 0x88760028UL: return "DDERR_CURRENTLYNOTAVAIL";
    case 0x88760037UL: return "DDERR_EXCEPTION";
    case 0x8876005AUL: return "DDERR_HEIGHTALIGN";
    case 0x88760078UL: return "DDERR_INCOMPATIBLEPRIMARY";
    case 0x88760082UL: return "DDERR_INVALIDCAPS";
    case 0x88760096UL: return "DDERR_INVALIDCLIPLIST";
    case 0x887600A0UL: return "DDERR_INVALIDMODE";
    case 0x887600AAUL: return "DDERR_INVALIDOBJECT";
    case 0x887600B4UL: return "DDERR_INVALIDPIXELFORMAT";
    case 0x887600BEUL: return "DDERR_INVALIDRECT";
    case 0x887600C8UL: return "DDERR_LOCKEDSURFACES";
    case 0x887600D2UL: return "DDERR_NO3D";
    case 0x887600DCUL: return "DDERR_NOALPHAHW";
    case 0x887600F0UL: return "DDERR_NOCLIPLIST";
    case 0x88760104UL: return "DDERR_NOCOLORCONVHW";
    case 0x8876010EUL: return "DDERR_NOCOOPERATIVELEVELSET";
    case 0x88760118UL: return "DDERR_NOCOLORKEY";
    case 0x88760122UL: return "DDERR_NOCOLORKEYHW";
    case 0x88760136UL: return "DDERR_NOEXCLUSIVEMODE";
    case 0x88760140UL: return "DDERR_NOFLIPHW";
    case 0x88760154UL: return "DDERR_NOGDI";
    case 0x8876015EUL: return "DDERR_NOMIRRORHW";
    case 0x88760168UL: return "DDERR_NOTFOUND";
    case 0x88760172UL: return "DDERR_NOOVERLAYHW";
    case 0x88760186UL: return "DDERR_NORASTEROPHW";
    case 0x88760190UL: return "DDERR_NOROTATIONHW";
    case 0x887601A4UL: return "DDERR_NOSTRETCHHW";
    case 0x887601B8UL: return "DDERR_NOT4BITCOLOR";
    case 0x887601C2UL: return "DDERR_NOT4BITCOLORINDEX";
    case 0x887601CCUL: return "DDERR_NOT8BITCOLOR";
    case 0x887601E0UL: return "DDERR_NOTEXTUREHW";
    case 0x887601EAUL: return "DDERR_NOVSYNCHW";
    case 0x887601F4UL: return "DDERR_NOZBUFFERHW";
    case 0x887601FEUL: return "DDERR_NOZOVERLAYHW";
    case 0x88760208UL: return "DDERR_OUTOFCAPS";
    case 0x88760212UL: return "DDERR_OUTOFMEMORY";
    case 0x8876021CUL: return "DDERR_OUTOFVIDEOMEMORY";
    case 0x8876023AUL: return "DDERR_OVERLAYCANTCLIP";
    case 0x88760244UL: return "DDERR_OVERLAYCOLORKEYONLYONEACTIVE";
    case 0x8876024EUL: return "DDERR_PALETTEBUSY";
    case 0x88760258UL: return "DDERR_COLORKEYNOTSET";
    case 0x88760262UL: return "DDERR_SURFACEALREADYATTACHED";
    case 0x8876026CUL: return "DDERR_SURFACEALREADYDEPENDENT";
    case 0x88760276UL: return "DDERR_SURFACEBUSY";
    case 0x88760280UL: return "DDERR_CANTLOCKSURFACE";
    case 0x8876028AUL: return "DDERR_SURFACEISOBSCURED";
    case 0x88760294UL: return "DDERR_SURFACELOST";
    case 0x8876029EUL: return "DDERR_SURFACENOTATTACHED";
    case 0x887602A8UL: return "DDERR_TOOBIGHEIGHT";
    case 0x887602B2UL: return "DDERR_TOOBIGSIZE";
    case 0x887602BCUL: return "DDERR_TOOBIGWIDTH";
    case 0x887602D0UL: return "DDERR_UNSUPPORTED";
    case 0x887602DAUL: return "DDERR_UNSUPPORTEDFORMAT";
    case 0x887602E4UL: return "DDERR_UNSUPPORTEDMASK";
    case 0x887602EEUL: return "DDERR_VERTICALBLANKINPROGRESS";
    case 0x887602F8UL: return "DDERR_WASSTILLDRAWING";
    case 0x8876030CUL: return "DDERR_XALIGN";
    case 0x88760316UL: return "DDERR_INVALIDDIRECTDRAWGUID";
    case 0x88760320UL: return "DDERR_DIRECTDRAWALREADYCREATED";
    case 0x8876032AUL: return "DDERR_NODIRECTDRAWHW";
    case 0x88760334UL: return "DDERR_PRIMARYSURFACEALREADYCREATED";
    case 0x8876033EUL: return "DDERR_NOEMULATION";
    case 0x88760348UL: return "DDERR_REGIONTOOSMALL";
    case 0x88760352UL: return "DDERR_CLIPPERISUSINGHWND";
    case 0x8876035CUL: return "DDERR_NOCLIPPERATTACHED";
    case 0x88760366UL: return "DDERR_NOHWND";
    case 0x88760370UL: return "DDERR_HWNDSUBCLASSED";
    case 0x8876037AUL: return "DDERR_HWNDALREADYSET";
    case 0x88760384UL: return "DDERR_NOPALETTEATTACHED";
    case 0x8876038EUL: return "DDERR_NOPALETTEHW";
    case 0x88760398UL: return "DDERR_BLTFASTCANTCLIP";
    case 0x887603A2UL: return "DDERR_NOBLTHW";
    case 0x887603ACUL: return "DDERR_NODDROPSHW";
    case 0x887603B6UL: return "DDERR_OVERLAYNOTVISIBLE";
    case 0x887603C0UL: return "DDERR_NOOVERLAYDEST";
    case 0x887603CAUL: return "DDERR_INVALIDPOSITION";
    case 0x887603D4UL: return "DDERR_NOTAOVERLAYSURFACE";
    case 0x887603DEUL: return "DDERR_EXCLUSIVEMODEALREADYSET";
    case 0x887603E8UL: return "DDERR_NOTFLIPPABLE";
    case 0x887603F2UL: return "DDERR_CANTDUPLICATE";
    case 0x887603FCUL: return "DDERR_NOTLOCKED";
    case 0x88760406UL: return "DDERR_CANTCREATEDC";
    case 0x88760410UL: return "DDERR_NODC";
    case 0x8876041AUL: return "DDERR_WRONGMODE";
    case 0x88760424UL: return "DDERR_IMPLICITLYCREATED";
    case 0x8876042EUL: return "DDERR_NOTPALETTIZED";
    case 0x88760438UL: return "DDERR_UNSUPPORTEDMODE";
    case 0x88760442UL: return "DDERR_NOMIPMAPHW";
    case 0x8876044CUL: return "DDERR_INVALIDSURFACETYPE";
    case 0x887604B8UL: return "DDERR_DCALREADYCREATED";
    case 0x8876051CUL: return "DDERR_CANTPAGELOCK";
    case 0x88760580UL: return "DDERR_CANTPAGEUNLOCK";
    case 0x887605E4UL: return "DDERR_NOTPAGELOCKED";
    default: return "?";
    }
}

static void flog(const char *fmt, ...)
{
    va_list ap;
    DWORD now = GetTickCount() - g_t0;
    if (!g_log)
        return;
    fprintf(g_log, "t=%lu ", (unsigned long)now);
    va_start(ap, fmt);
    vfprintf(g_log, fmt, ap);
    va_end(ap);
    fputc('\n', g_log);
    fflush(g_log);
}

static void log_hr(const char *what, HRESULT hr)
{
    flog("%s hr=0x%08lX (%ld) %s", what,
         (unsigned long)(ULONG)hr, (long)hr, hr_name(hr));
}

static void dump_ddsd(const char *what, const DDSURFACEDESC *d)
{
    flog("%s flags=0x%08lx caps=0x%08lx %ux%u pitch=%ld bpp=%u pf_flags=0x%08lx lpSurface=%p",
         what, (unsigned long)d->dwFlags,
         (unsigned long)((d->dwFlags & DDSD_CAPS) ? d->ddsCaps.dwCaps : 0),
         (unsigned)((d->dwFlags & DDSD_WIDTH) ? d->dwWidth : 0),
         (unsigned)((d->dwFlags & DDSD_HEIGHT) ? d->dwHeight : 0),
         (long)((d->dwFlags & DDSD_PITCH) ? d->lPitch : -1),
         (unsigned)((d->dwFlags & DDSD_PIXELFORMAT) ? d->ddpfPixelFormat.dwRGBBitCount : 0),
         (unsigned long)((d->dwFlags & DDSD_PIXELFORMAT) ? d->ddpfPixelFormat.dwFlags : 0),
         d->lpSurface);
}

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    WNDCLASSA wc;
    HWND hwnd;
    LPDIRECTDRAW dd = NULL;
    LPDIRECTDRAWPALETTE pal = NULL;
    LPDIRECTDRAWSURFACE off = NULL;
    LPDIRECTDRAWSURFACE prim = NULL;
    DDSURFACEDESC ddsd;
    DDSCAPS caps;
    PALETTEENTRY entries[256];
    HRESULT hr;
    RECT dst, src;
    int i;
    (void)prev;
    (void)cmd;
    (void)show;
    g_t0 = GetTickCount();
    g_log = fopen("Z:\\tmp\\ss1-cnc-ddraw.log", "w");
    if (!g_log)
        g_log = fopen("ss1-cnc-ddraw.log", "w");
    if (g_log)
        setvbuf(g_log, NULL, _IONBF, 0);
    flog("ddraw-probe start pid=%lu", (unsigned long)GetCurrentProcessId());

    memset(&wc, 0, sizeof wc);
    wc.lpfnWndProc = wndproc;
    wc.hInstance = inst;
    wc.lpszClassName = "ss1cncdd";
    wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    RegisterClassA(&wc);
    hwnd = CreateWindowExA(0, "ss1cncdd", "ss1-cnc-ddraw",
                           WS_POPUP, 0, 0, 640, 480, NULL, NULL, inst, NULL);
    flog("hwnd=%p", (void *)hwnd);
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    SetForegroundWindow(hwnd);

    hr = DirectDrawCreate(NULL, &dd, NULL);
    log_hr("DirectDrawCreate", hr);
    if (FAILED(hr) || !dd)
        goto out;

    hr = IDirectDraw_SetCooperativeLevel(dd, hwnd, DDSCL_FULLSCREEN | DDSCL_EXCLUSIVE);
    log_hr("SetCooperativeLevel FULLSCREEN|EXCLUSIVE", hr);

    hr = IDirectDraw_SetDisplayMode(dd, 640, 480, 8);
    log_hr("SetDisplayMode(640,480,8)", hr);

    memset(entries, 0, sizeof entries);
    for (i = 0; i < 256; i++) {
        entries[i].peRed = (BYTE)i;
        entries[i].peGreen = (BYTE)i;
        entries[i].peBlue = (BYTE)i;
        entries[i].peFlags = 0;
    }
    hr = IDirectDraw_CreatePalette(dd, DDPCAPS_8BIT | DDPCAPS_ALLOW256, entries, &pal, NULL);
    log_hr("CreatePalette 8BIT|ALLOW256", hr);

    memset(&ddsd, 0, sizeof ddsd);
    ddsd.dwSize = sizeof ddsd;
    ddsd.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT;
    ddsd.ddsCaps.dwCaps = DDSCAPS_OFFSCREENPLAIN;
    ddsd.dwWidth = 64;
    ddsd.dwHeight = 64;
    hr = IDirectDraw_CreateSurface(dd, &ddsd, &off, NULL);
    log_hr("CreateSurface OFFSCREENPLAIN 64x64", hr);
    if (SUCCEEDED(hr) && off) {
        memset(&ddsd, 0, sizeof ddsd);
        ddsd.dwSize = sizeof ddsd;
        hr = IDirectDrawSurface_Lock(off, NULL, &ddsd, DDLOCK_WAIT, NULL);
        log_hr("Lock offscreen DDLOCK_WAIT", hr);
        if (SUCCEEDED(hr)) {
            dump_ddsd("offscreen locked", &ddsd);
            hr = IDirectDrawSurface_Unlock(off, NULL);
            log_hr("Unlock offscreen", hr);
        }
        SetRect(&dst, 0, 1, 64, 64);
        SetRect(&src, 0, 0, 64, 63);
        hr = IDirectDrawSurface_Blt(off, &dst, off, &src, DDBLT_WAIT | DDBLT_DDROPS, NULL);
        log_hr("Blt overlap DDBLT_WAIT|DDBLT_DDROPS", hr);
    }

    memset(&ddsd, 0, sizeof ddsd);
    ddsd.dwSize = sizeof ddsd;
    ddsd.dwFlags = DDSD_CAPS;
    ddsd.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    hr = IDirectDraw_CreateSurface(dd, &ddsd, &prim, NULL);
    log_hr("CreateSurface PRIMARYSURFACE", hr);

    if (SUCCEEDED(hr) && prim) {
        memset(&caps, 0, sizeof caps);
        hr = IDirectDrawSurface_GetCaps(prim, &caps);
        log_hr("primary GetCaps", hr);
        flog("primary caps=0x%08lx", (unsigned long)caps.dwCaps);

        memset(&ddsd, 0, sizeof ddsd);
        ddsd.dwSize = sizeof ddsd;
        hr = IDirectDrawSurface_GetSurfaceDesc(prim, &ddsd);
        log_hr("primary GetSurfaceDesc", hr);
        if (SUCCEEDED(hr))
            dump_ddsd("primary desc", &ddsd);

        memset(&ddsd, 0, sizeof ddsd);
        ddsd.dwSize = sizeof ddsd;
        hr = IDirectDrawSurface_Lock(prim, NULL, &ddsd, DDLOCK_WAIT, NULL);
        log_hr("primary Lock DDLOCK_WAIT", hr);
        if (SUCCEEDED(hr)) {
            dump_ddsd("primary locked", &ddsd);
            if (ddsd.lpSurface && ddsd.lPitch > 0) {
                memset(ddsd.lpSurface, 0x20, (size_t)ddsd.lPitch);
                flog("wrote first pitch row with index 0x20");
            }
            hr = IDirectDrawSurface_Unlock(prim, NULL);
            log_hr("primary Unlock", hr);
        }

        if (pal) {
            hr = IDirectDrawSurface_SetPalette(prim, pal);
            log_hr("primary SetPalette", hr);
        }
        if (off) {
            SetRect(&dst, 0, 0, 64, 64);
            hr = IDirectDrawSurface_Blt(prim, &dst, off, NULL, DDBLT_WAIT, NULL);
            log_hr("Blt offscreen->primary DDBLT_WAIT", hr);
            hr = IDirectDrawSurface_BltFast(prim, 8, 8, off, NULL, DDBLTFAST_WAIT);
            log_hr("BltFast offscreen->primary DDBLTFAST_WAIT", hr);
        }
    }

    /* Explicit VIDEOMEMORY requests. Do not change Wine config; just ask. */
    {
        static const struct {
            const char *name;
            DWORD caps;
            DWORD w, h;
        } reqs[] = {
            { "A OFFSCREENPLAIN|VIDEOMEMORY 64x64",
              DDSCAPS_OFFSCREENPLAIN | DDSCAPS_VIDEOMEMORY, 64, 64 },
            { "B OFFSCREENPLAIN|VIDEOMEMORY 640x480",
              DDSCAPS_OFFSCREENPLAIN | DDSCAPS_VIDEOMEMORY, 640, 480 },
            { "C OFFSCREENPLAIN|VIDEOMEMORY|LOCALVIDMEM 64x64",
              DDSCAPS_OFFSCREENPLAIN | DDSCAPS_VIDEOMEMORY | DDSCAPS_LOCALVIDMEM, 64, 64 },
        };
        unsigned ri;
        for (ri = 0; ri < sizeof reqs / sizeof reqs[0]; ri++) {
            LPDIRECTDRAWSURFACE s = NULL;
            memset(&ddsd, 0, sizeof ddsd);
            ddsd.dwSize = sizeof ddsd;
            ddsd.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT;
            ddsd.ddsCaps.dwCaps = reqs[ri].caps;
            ddsd.dwWidth = reqs[ri].w;
            ddsd.dwHeight = reqs[ri].h;
            hr = IDirectDraw_CreateSurface(dd, &ddsd, &s, NULL);
            log_hr(reqs[ri].name, hr);
            if (SUCCEEDED(hr) && s) {
                memset(&caps, 0, sizeof caps);
                hr = IDirectDrawSurface_GetCaps(s, &caps);
                log_hr("  GetCaps", hr);
                flog("  returned caps=0x%08lx", (unsigned long)caps.dwCaps);
                memset(&ddsd, 0, sizeof ddsd);
                ddsd.dwSize = sizeof ddsd;
                hr = IDirectDrawSurface_Lock(s, NULL, &ddsd, DDLOCK_WAIT, NULL);
                log_hr("  Lock DDLOCK_WAIT", hr);
                if (SUCCEEDED(hr)) {
                    dump_ddsd("  locked", &ddsd);
                    IDirectDrawSurface_Unlock(s, NULL);
                }
                IDirectDrawSurface_Release(s);
            }
        }
    }

    Sleep(400);

    if (off)
        IDirectDrawSurface_Release(off);
    if (prim)
        IDirectDrawSurface_Release(prim);
    if (pal)
        IDirectDrawPalette_Release(pal);
    if (dd) {
        IDirectDraw_RestoreDisplayMode(dd);
        IDirectDraw_SetCooperativeLevel(dd, hwnd, DDSCL_NORMAL);
        IDirectDraw_Release(dd);
    }
    DestroyWindow(hwnd);
    flog("ddraw-probe done");
    if (g_log)
        fclose(g_log);
    return 0;
out:
    if (dd)
        IDirectDraw_Release(dd);
    if (hwnd)
        DestroyWindow(hwnd);
    if (g_log)
        fclose(g_log);
    return 1;
}
