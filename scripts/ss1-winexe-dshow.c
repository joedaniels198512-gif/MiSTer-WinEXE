/* Minimal Wine DirectShow PCM WAV graph test. No WMP, no UI.
 * Compile: i686-w64-mingw32-gcc -O2 -o ss1-winexe-dshow.exe \
 *            ss1-winexe-dshow.c -lole32 -loleaut32 -lstrmiids -luuid
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define CINTERFACE
#include <windows.h>
#include <ole2.h>
#include <dshow.h>
#include <stdio.h>

static const WCHAR kWav[] = L"C:\\tone.wav";

static int utf8_to_wide(const char *s, WCHAR *out, int nout)
{
    return MultiByteToWideChar(CP_ACP, 0, s, -1, out, nout);
}
static const WCHAR kWaveParser[] = L"{D51BD5A1-7548-11CF-A520-0080C77EF58A}";
static const WCHAR kAudioRender[] = L"{E30629D1-27E5-11CE-875D-00608CB78066}";

static IBaseFilter *find_filter_clsid(IGraphBuilder *gb, REFCLSID want)
{
    IEnumFilters *en = NULL;
    IBaseFilter *f = NULL, *found = NULL;

    if (FAILED(IGraphBuilder_EnumFilters(gb, &en)) || !en)
        return NULL;
    while (!found && IEnumFilters_Next(en, 1, &f, NULL) == S_OK && f) {
        IPersist *persist = NULL;
        CLSID id;
        if (SUCCEEDED(IBaseFilter_QueryInterface(f, &IID_IPersist, (void **)&persist)) && persist) {
            if (SUCCEEDED(IPersist_GetClassID(persist, &id)) && IsEqualGUID(&id, want))
                found = f;
            IPersist_Release(persist);
        }
        if (!found) {
            IBaseFilter_Release(f);
            f = NULL;
        }
    }
    IEnumFilters_Release(en);
    return found;
}

static IPin *find_pin(IBaseFilter *f, PIN_DIRECTION want, int must_connected)
{
    IEnumPins *en = NULL;
    IPin *pin = NULL, *found = NULL;

    if (!f || FAILED(IBaseFilter_EnumPins(f, &en)) || !en)
        return NULL;
    while (!found && IEnumPins_Next(en, 1, &pin, NULL) == S_OK && pin) {
        PIN_DIRECTION dir = PINDIR_INPUT;
        IPin *peer = NULL;
        IPin_QueryDirection(pin, &dir);
        if (dir == want) {
            int conn = SUCCEEDED(IPin_ConnectedTo(pin, &peer)) && peer;
            if (peer)
                IPin_Release(peer);
            if ((must_connected && conn) || (!must_connected && !conn))
                found = pin;
        }
        if (!found) {
            IPin_Release(pin);
            pin = NULL;
        }
    }
    IEnumPins_Release(en);
    return found;
}

/* RenderFile picks DSound. Swap in quartz WaveOut (CLSID_AudioRender) and
 * ConnectDirect so Intelligent Connect cannot put DSound back. */
static HRESULT force_waveout(IGraphBuilder *gb)
{
    IBaseFilter *ds = NULL, *wo = NULL;
    IPin *dsin = NULL, *split = NULL, *woin = NULL;
    HRESULT hr;

    hr = CoCreateInstance(&CLSID_AudioRender, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IBaseFilter, (void **)&wo);
    print_hr("CLSID_AudioRender CoCreate", hr);
    if (FAILED(hr) || !wo)
        return hr;

    ds = find_filter_clsid(gb, &CLSID_DSoundRender);
    if (!ds) {
        printf("FAIL no DirectSound renderer in graph\n");
        IBaseFilter_Release(wo);
        return E_FAIL;
    }

    dsin = find_pin(ds, PINDIR_INPUT, 1);
    if (dsin) {
        hr = IPin_ConnectedTo(dsin, &split);
        print_hr("DSound ConnectedTo", hr);
    }
    if (dsin) {
        hr = IGraphBuilder_Disconnect(gb, dsin);
        print_hr("Disconnect DSound input", hr);
    }
    if (split) {
        hr = IGraphBuilder_Disconnect(gb, split);
        print_hr("Disconnect splitter output", hr);
    }

    hr = IGraphBuilder_RemoveFilter(gb, ds);
    print_hr("RemoveFilter DSound", hr);
    IBaseFilter_Release(ds);
    if (dsin)
        IPin_Release(dsin);

    hr = IGraphBuilder_AddFilter(gb, wo, L"waveout");
    print_hr("AddFilter WaveOut", hr);
    if (FAILED(hr))
        goto done;

    woin = find_pin(wo, PINDIR_INPUT, 0);
    if (!woin || !split) {
        printf("FAIL WaveOut input or splitter output pin missing\n");
        hr = E_FAIL;
        goto done;
    }
    hr = IGraphBuilder_ConnectDirect(gb, split, woin, NULL);
    print_hr("ConnectDirect splitter->WaveOut", hr);
    if (FAILED(hr)) {
        printf("FAIL refusing IGraphBuilder_Connect (would allow DSound again)\n");
        goto done;
    }
    {
        IBaseFilter *still = find_filter_clsid(gb, &CLSID_DSoundRender);
        if (still) {
            printf("FAIL DirectSound still in graph after WaveOut swap\n");
            IBaseFilter_Release(still);
            hr = E_FAIL;
        }
    }

done:
    if (woin)
        IPin_Release(woin);
    if (split)
        IPin_Release(split);
    IBaseFilter_Release(wo);
    return hr;
}

static void print_hr(const char *label, HRESULT hr)
{
    unsigned u = (unsigned)hr;
    if (hr == S_OK)
        printf("%s hr=0x%08X S_OK\n", label, u);
    else if (hr == S_FALSE)
        printf("%s hr=0x%08X S_FALSE\n", label, u);
    else
        printf("%s hr=0x%08X\n", label, u);
    fflush(stdout);
}

static void print_w(const char *label, const WCHAR *w)
{
    char buf[256];
    buf[0] = 0;
    if (w)
        WideCharToMultiByte(CP_ACP, 0, w, -1, buf, (int)sizeof buf, NULL, NULL);
    printf("%s %s\n", label, buf);
    fflush(stdout);
}

static HRESULT try_clsid(const char *label, const WCHAR *clsidw)
{
    CLSID clsid;
    IUnknown *unk = NULL;
    HRESULT hr;

    hr = CLSIDFromString((LPOLESTR)clsidw, &clsid);
    if (FAILED(hr)) {
        print_hr(label, hr);
        printf("%s CLSIDFromString failed\n", label);
        return hr;
    }
    hr = CoCreateInstance(&clsid, NULL, CLSCTX_INPROC_SERVER, &IID_IUnknown, (void **)&unk);
    print_hr(label, hr);
    if (unk)
        IUnknown_Release(unk);
    return hr;
}

static void enum_filters(IGraphBuilder *gb)
{
    IEnumFilters *en = NULL;
    IBaseFilter *f = NULL;
    HRESULT hr;
    int n = 0;

    hr = IGraphBuilder_EnumFilters(gb, &en);
    print_hr("EnumFilters", hr);
    if (FAILED(hr) || !en)
        return;
    while (IEnumFilters_Next(en, 1, &f, NULL) == S_OK && f) {
        FILTER_INFO fi;
        IPersist *persist = NULL;
        CLSID clsid;
        WCHAR *clsidw = NULL;

        memset(&fi, 0, sizeof fi);
        IBaseFilter_QueryFilterInfo(f, &fi);
        print_w("FILTER name", fi.achName);
        if (fi.pGraph)
            IFilterGraph_Release(fi.pGraph);
        if (SUCCEEDED(IBaseFilter_QueryInterface(f, &IID_IPersist, (void **)&persist)) && persist) {
            if (SUCCEEDED(IPersist_GetClassID(persist, &clsid)) &&
                SUCCEEDED(StringFromCLSID(&clsid, &clsidw)) && clsidw) {
                print_w("FILTER clsid", clsidw);
                CoTaskMemFree(clsidw);
            }
            IPersist_Release(persist);
        }
        IBaseFilter_Release(f);
        f = NULL;
        n++;
        if (n > 16)
            break;
    }
    printf("FILTER count=%d\n", n);
    fflush(stdout);
    IEnumFilters_Release(en);
}

static const char *state_name(OAFilterState st)
{
    switch (st) {
    case State_Stopped: return "Stopped";
    case State_Paused: return "Paused";
    case State_Running: return "Running";
    default: return "?";
    }
}

int main(int argc, char **argv)
{
    IGraphBuilder *gb = NULL;
    IMediaControl *mc = NULL;
    IMediaSeeking *ms = NULL;
    IMediaEvent *me = NULL;
    HRESULT hr, rc = E_FAIL;
    LONGLONG dur = 0, pos = 0;
    OAFilterState st = State_Stopped;
    LONG ev = 0;
    int i, max_i;
    WCHAR wavpath[MAX_PATH];
    const WCHAR *wav = kWav;

    if (argc > 1 && argv[1] && argv[1][0]) {
        if (utf8_to_wide(argv[1], wavpath, MAX_PATH) > 0)
            wav = wavpath;
    }

    printf("DSHOW argc=%d\n", argc);
    print_w("DSHOW wav", wav);
    fflush(stdout);

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    print_hr("CoInitializeEx", hr);
    if (FAILED(hr) && hr != S_FALSE)
        return 2;

    hr = try_clsid("WaveParser", kWaveParser);
    if (FAILED(hr)) {
        CoUninitialize();
        return 3;
    }
    hr = try_clsid("AudioRenderWaveOut", kAudioRender);
    if (FAILED(hr)) {
        CoUninitialize();
        return 3;
    }

    hr = CoCreateInstance(&CLSID_FilterGraph, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IGraphBuilder, (void **)&gb);
    print_hr("FilterGraph/IGraphBuilder", hr);
    if (FAILED(hr) || !gb)
        goto out;

    printf("BEFORE RenderFile\n");
    fflush(stdout);
    hr = IGraphBuilder_RenderFile(gb, wav, NULL);
    print_hr("RenderFile", hr);
    rc = hr;
    printf("FILTERS after RenderFile (may include DirectSound)\n");
    enum_filters(gb);
    if (FAILED(hr))
        goto out;

    hr = force_waveout(gb);
    print_hr("force_waveout", hr);
    printf("FILTERS after WaveOut swap\n");
    enum_filters(gb);
    if (FAILED(hr)) {
        rc = hr;
        goto out;
    }

    IGraphBuilder_QueryInterface(gb, &IID_IMediaSeeking, (void **)&ms);
    IGraphBuilder_QueryInterface(gb, &IID_IMediaControl, (void **)&mc);
    IGraphBuilder_QueryInterface(gb, &IID_IMediaEvent, (void **)&me);
    if (!mc) {
        printf("FAIL IMediaControl\n");
        rc = E_NOINTERFACE;
        goto out;
    }

    if (ms) {
        dur = 0;
        hr = IMediaSeeking_GetDuration(ms, &dur);
        print_hr("GetDuration", hr);
        printf("DURATION 100ns=%lld ms=%lld\n",
               (long long)dur, (long long)(dur / 10000));
        fflush(stdout);
    }

    hr = IMediaControl_GetState(mc, 1000, &st);
    print_hr("GetState before Run", hr);
    printf("STATE before Run %s\n", state_name(st));

    printf("BEFORE Run\n");
    fflush(stdout);
    hr = IMediaControl_Run(mc);
    print_hr("Run", hr);
    if (FAILED(hr)) {
        rc = hr;
        goto stop;
    }

    hr = IMediaControl_GetState(mc, 2000, &st);
    print_hr("GetState after Run", hr);
    printf("STATE after Run %s\n", state_name(st));
    fflush(stdout);

    max_i = 80;
    if (dur > 0) {
        max_i = (int)((dur / 10000) / 500) + 12;
        if (max_i < 8)
            max_i = 8;
        if (max_i > 120)
            max_i = 120;
    }
    printf("POLL max_i=%d (~%ds)\n", max_i, max_i / 2);
    fflush(stdout);
    for (i = 0; i < max_i; i++) {
        pos = -1;
        if (ms)
            IMediaSeeking_GetCurrentPosition(ms, &pos);
        IMediaControl_GetState(mc, 0, &st);
        printf("POS i=%d 100ns=%lld ms=%lld state=%s\n",
               i, (long long)pos, (long long)(pos / 10000), state_name(st));
        fflush(stdout);
        if (me) {
            ev = 0;
            hr = IMediaEvent_WaitForCompletion(me, 500, &ev);
            if (hr == S_OK) {
                printf("WAIT complete ev=0x%lx\n", (unsigned long)ev);
                fflush(stdout);
                break;
            }
        } else {
            Sleep(500);
        }
        if (ms && dur > 0 && pos >= dur)
            break;
    }

    if (ms) {
        pos = -1;
        IMediaSeeking_GetCurrentPosition(ms, &pos);
        printf("POS final 100ns=%lld ms=%lld duration_ms=%lld\n",
               (long long)pos, (long long)(pos / 10000), (long long)(dur / 10000));
        fflush(stdout);
    }
    rc = S_OK;

stop:
    if (mc)
        IMediaControl_Stop(mc);

out:
    if (me)
        IMediaEvent_Release(me);
    if (ms)
        IMediaSeeking_Release(ms);
    if (mc)
        IMediaControl_Release(mc);
    if (gb)
        IGraphBuilder_Release(gb);
    CoUninitialize();
    print_hr("DSHOW done", rc);
    return FAILED(rc) ? 1 : 0;
}
