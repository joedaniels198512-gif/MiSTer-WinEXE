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
static const WCHAR kWaveParser[] = L"{D51BD5A1-7548-11CF-A520-0080C77EF58A}";

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

int main(void)
{
    IGraphBuilder *gb = NULL;
    IMediaControl *mc = NULL;
    IMediaSeeking *ms = NULL;
    IMediaEvent *me = NULL;
    HRESULT hr, rc = E_FAIL;
    LONGLONG dur = 0, pos = 0;
    OAFilterState st = State_Stopped;
    LONG ev = 0;
    int i;

    printf("DSHOW start wav=C:\\tone.wav\n");
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

    hr = CoCreateInstance(&CLSID_FilterGraph, NULL, CLSCTX_INPROC_SERVER,
                          &IID_IGraphBuilder, (void **)&gb);
    print_hr("FilterGraph/IGraphBuilder", hr);
    if (FAILED(hr) || !gb)
        goto out;

    printf("BEFORE RenderFile\n");
    fflush(stdout);
    hr = IGraphBuilder_RenderFile(gb, kWav, NULL);
    print_hr("RenderFile", hr);
    rc = hr;
    enum_filters(gb);
    if (FAILED(hr))
        goto out;

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

    for (i = 0; i < 8; i++) {
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
