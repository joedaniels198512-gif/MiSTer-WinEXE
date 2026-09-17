/* Shared WMP graph rewrite: replace DirectSound with SS1 WaveOut.
 * Included by ss1-winexe-wmpinj.c and ss1-winexe-wmpwo.c.
 * LoadLibrary + DllGetClassObject only — no regsvr32, no merit changes.
 */
#ifndef SS1_WMPWO_GRAPH_C
#define SS1_WMPWO_GRAPH_C

static const CLSID CLSID_GSTSplitter =
    {0xF9D8D64E, 0xA144, 0x47DC, {0x8E, 0xE0, 0xF5, 0x34, 0x98, 0x37, 0x2C, 0x29}};
static const CLSID CLSID_WaveParser =
    {0xD51BD5A1, 0x7548, 0x11CF, {0xA5, 0x20, 0x00, 0x80, 0xC7, 0x7E, 0xF5, 0x8A}};
static const CLSID CLSID_AsyncReader =
    {0xE436EBB5, 0x524F, 0x11CE, {0x9F, 0x53, 0x00, 0x20, 0xAF, 0x0B, 0xA7, 0x70}};

typedef HRESULT (WINAPI *PFN_DllGetClassObject)(REFCLSID, REFIID, void **);

static HMODULE g_ss1wo_mod;
static FILE *g_wmpwo_file;
static LONG g_wmpwo_swaps;
static LONG g_wmpwo_dsound_seen;
static LONG g_wmpwo_ss1_ok;
static LONG g_wmpwo_rebuilds;
static DWORD g_wmpwo_last_graph;
static DWORD g_wmpwo_graphs_now;

static void wmpwo_log(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    printf("WMPWO: ");
    vprintf(fmt, ap);
    va_end(ap);
    fflush(stdout);
    if (!g_wmpwo_file) {
        g_wmpwo_file = fopen("C:\\windows\\temp\\ss1wmpwo.log", "a");
        if (!g_wmpwo_file)
            g_wmpwo_file = fopen("C:\\ss1wmpwo.log", "a");
    }
    if (g_wmpwo_file) {
        va_start(ap, fmt);
        fprintf(g_wmpwo_file, "WMPWO: ");
        vfprintf(g_wmpwo_file, fmt, ap);
        va_end(ap);
        fflush(g_wmpwo_file);
    }
}

static void wmpwo_log_w(const char *label, const WCHAR *w)
{
    char buf[256];
    buf[0] = 0;
    if (w)
        WideCharToMultiByte(CP_ACP, 0, w, -1, buf, (int)sizeof buf, NULL, NULL);
    wmpwo_log("%s %s\n", label, buf);
}

static void wmpwo_log_hr(const char *label, HRESULT hr)
{
    if (hr == S_OK)
        wmpwo_log("%s hr=0x%08X S_OK\n", label, (unsigned)hr);
    else if (hr == S_FALSE)
        wmpwo_log("%s hr=0x%08X S_FALSE\n", label, (unsigned)hr);
    else
        wmpwo_log("%s hr=0x%08X\n", label, (unsigned)hr);
}

static int guid_eq(const GUID *a, const GUID *b)
{
    return a && b && IsEqualGUID(a, b);
}

static int is_dsound_clsid(const CLSID *id)
{
    return guid_eq(id, &CLSID_DSoundRender) || guid_eq(id, &CLSID_AudioRender);
}

static int is_ss1_clsid(const CLSID *id)
{
    return guid_eq(id, &CLSID_SS1WaveOut);
}

static HRESULT persist_clsid(IBaseFilter *f, CLSID *id)
{
    IPersist *p = NULL;
    HRESULT hr;
    ZeroMemory(id, sizeof *id);
    if (FAILED(IBaseFilter_QueryInterface(f, &IID_IPersist, (void **)&p)) || !p)
        return E_NOINTERFACE;
    hr = IPersist_GetClassID(p, id);
    IPersist_Release(p);
    return hr;
}

static void filter_name(IBaseFilter *f, WCHAR *out, int nout)
{
    FILTER_INFO fi;
    memset(&fi, 0, sizeof fi);
    out[0] = 0;
    if (SUCCEEDED(IBaseFilter_QueryFilterInfo(f, &fi))) {
        lstrcpynW(out, fi.achName, nout);
        if (fi.pGraph)
            IFilterGraph_Release(fi.pGraph);
    }
}

static int name_is_dsound(const WCHAR *name)
{
    return name && wcsstr(name, L"DirectSound");
}

static IPin *find_pin_dir(IBaseFilter *f, PIN_DIRECTION want, int must_connected)
{
    IEnumPins *en = NULL;
    IPin *pin = NULL, *found = NULL;

    if (!f || FAILED(IBaseFilter_EnumPins(f, &en)) || !en)
        return NULL;
    while (!found && IEnumPins_Next(en, 1, &pin, NULL) == S_OK && pin) {
        PIN_DIRECTION dir = PINDIR_INPUT;
        IPin *peer = NULL;
        int conn;
        IPin_QueryDirection(pin, &dir);
        conn = SUCCEEDED(IPin_ConnectedTo(pin, &peer)) && peer;
        if (peer)
            IPin_Release(peer);
        if (dir == want && ((must_connected && conn) || (!must_connected && !conn)))
            found = pin;
        if (!found) {
            IPin_Release(pin);
            pin = NULL;
        }
    }
    IEnumPins_Release(en);
    return found;
}

static IBaseFilter *find_filter_by_clsid(IGraphBuilder *gb, REFCLSID want)
{
    IEnumFilters *en = NULL;
    IBaseFilter *f = NULL, *found = NULL;

    if (FAILED(IGraphBuilder_EnumFilters(gb, &en)) || !en)
        return NULL;
    while (!found && IEnumFilters_Next(en, 1, &f, NULL) == S_OK && f) {
        CLSID id;
        if (SUCCEEDED(persist_clsid(f, &id)) && guid_eq(&id, want))
            found = f;
        if (!found) {
            IBaseFilter_Release(f);
            f = NULL;
        }
    }
    IEnumFilters_Release(en);
    return found;
}

static void enum_graph(IGraphBuilder *gb, int *n_ds, int *n_ss1, int *n_gst, int *n_all)
{
    IEnumFilters *en = NULL;
    IBaseFilter *f = NULL;
    int n = 0, ds = 0, ss1 = 0, gst = 0;

    if (n_ds) *n_ds = 0;
    if (n_ss1) *n_ss1 = 0;
    if (n_gst) *n_gst = 0;
    if (n_all) *n_all = 0;
    if (FAILED(IGraphBuilder_EnumFilters(gb, &en)) || !en)
        return;
    while (IEnumFilters_Next(en, 1, &f, NULL) == S_OK && f) {
        FILTER_INFO fi;
        CLSID id;
        WCHAR *clsidw = NULL;
        char nbuf[128], cbuf[80];

        memset(&fi, 0, sizeof fi);
        IBaseFilter_QueryFilterInfo(f, &fi);
        persist_clsid(f, &id);
        nbuf[0] = cbuf[0] = 0;
        WideCharToMultiByte(CP_ACP, 0, fi.achName, -1, nbuf, (int)sizeof nbuf, NULL, NULL);
        if (SUCCEEDED(StringFromCLSID(&id, &clsidw)) && clsidw) {
            WideCharToMultiByte(CP_ACP, 0, clsidw, -1, cbuf, (int)sizeof cbuf, NULL, NULL);
            CoTaskMemFree(clsidw);
        }
        wmpwo_log("FILTER name=%s clsid=%s\n", nbuf, cbuf);
        if (is_dsound_clsid(&id) || name_is_dsound(fi.achName))
            ds++;
        if (is_ss1_clsid(&id) || wcsstr(fi.achName, L"SS1 WaveOut"))
            ss1++;
        if (guid_eq(&id, &CLSID_GSTSplitter) || guid_eq(&id, &CLSID_WaveParser) ||
            guid_eq(&id, &CLSID_AsyncReader))
            gst++;
        if (fi.pGraph)
            IFilterGraph_Release(fi.pGraph);
        IBaseFilter_Release(f);
        f = NULL;
        n++;
        if (n > 24)
            break;
    }
    IEnumFilters_Release(en);
    wmpwo_log("FILTER count=%d dsound=%d ss1=%d src/split=%d\n", n, ds, ss1, gst);
    if (n_ds) *n_ds = ds;
    if (n_ss1) *n_ss1 = ss1;
    if (n_gst) *n_gst = gst;
    if (n_all) *n_all = n;
}

static HRESULT load_ss1_filter(IBaseFilter **out)
{
    WCHAR paths[4][MAX_PATH];
    UINT i, n = 0;
    PFN_DllGetClassObject pfn;
    IClassFactory *cf = NULL;
    HRESULT hr;

    *out = NULL;
    lstrcpyW(paths[n++], L"C:\\windows\\system32\\ss1waveout.ax");
    lstrcpyW(paths[n++], L"C:\\ss1waveout.ax");
    lstrcpyW(paths[n++], L"ss1waveout.ax");
    if (!g_ss1wo_mod) {
        for (i = 0; i < n && !g_ss1wo_mod; i++) {
            SetLastError(0);
            g_ss1wo_mod = LoadLibraryW(paths[i]);
            wmpwo_log("LoadLibraryW ax i=%u handle=%p gle=%lu\n",
                      i, (void *)g_ss1wo_mod, (unsigned long)GetLastError());
        }
    }
    if (!g_ss1wo_mod)
        return HRESULT_FROM_WIN32(ERROR_MOD_NOT_FOUND);
    pfn = (PFN_DllGetClassObject)GetProcAddress(g_ss1wo_mod, "DllGetClassObject");
    if (!pfn)
        return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    hr = pfn(&CLSID_SS1WaveOut, &IID_IClassFactory, (void **)&cf);
    if (FAILED(hr) || !cf)
        return FAILED(hr) ? hr : E_FAIL;
    hr = IClassFactory_CreateInstance(cf, NULL, &IID_IBaseFilter, (void **)out);
    IClassFactory_Release(cf);
    return hr;
}

static IPin *find_audio_src_pin(IGraphBuilder *gb)
{
    IBaseFilter *f;
    IPin *pin;

    f = find_filter_by_clsid(gb, &CLSID_GSTSplitter);
    if (f) {
        pin = find_pin_dir(f, PINDIR_OUTPUT, 0);
        IBaseFilter_Release(f);
        if (pin)
            return pin;
    }
    f = find_filter_by_clsid(gb, &CLSID_WaveParser);
    if (f) {
        pin = find_pin_dir(f, PINDIR_OUTPUT, 0);
        IBaseFilter_Release(f);
        if (pin)
            return pin;
    }
    return NULL;
}

static HRESULT force_ss1_on_graph(IGraphBuilder *gb)
{
    IBaseFilter *ds = NULL, *wo = NULL, *still = NULL, *f = NULL, *existing = NULL;
    IEnumFilters *en = NULL;
    IPin *dsin = NULL, *split = NULL, *woin = NULL;
    IMediaControl *mc = NULL;
    OAFilterState st = State_Stopped, st2 = State_Stopped;
    HRESULT hr;
    int paused = 0;

    existing = find_filter_by_clsid(gb, &CLSID_SS1WaveOut);

    ds = find_filter_by_clsid(gb, &CLSID_DSoundRender);
    if (!ds)
        ds = find_filter_by_clsid(gb, &CLSID_AudioRender);
    if (!ds && SUCCEEDED(IGraphBuilder_EnumFilters(gb, &en)) && en) {
        while (!ds && IEnumFilters_Next(en, 1, &f, NULL) == S_OK && f) {
            WCHAR name[128];
            filter_name(f, name, 128);
            if (name_is_dsound(name))
                ds = f;
            else
                IBaseFilter_Release(f);
            f = NULL;
        }
        IEnumFilters_Release(en);
    }

    if (ds) {
        InterlockedIncrement(&g_wmpwo_dsound_seen);
        dsin = find_pin_dir(ds, PINDIR_INPUT, 1);
        if (dsin)
            IPin_ConnectedTo(dsin, &split);
    }

    if (SUCCEEDED(IGraphBuilder_QueryInterface(gb, &IID_IMediaControl, (void **)&mc)) && mc) {
        IMediaControl_GetState(mc, 200, &st);
        if (st == State_Running) {
            hr = IMediaControl_Pause(mc);
            wmpwo_log_hr("Pause for swap", hr);
            IMediaControl_GetState(mc, 1500, &st2);
            paused = 1;
        }
    }

    if (dsin) {
        hr = IGraphBuilder_Disconnect(gb, dsin);
        wmpwo_log_hr("Disconnect DSound input", hr);
    }
    if (split) {
        hr = IGraphBuilder_Disconnect(gb, split);
        wmpwo_log_hr("Disconnect splitter output", hr);
    }
    if (ds) {
        hr = IGraphBuilder_RemoveFilter(gb, ds);
        wmpwo_log_hr("RemoveFilter DSound", hr);
        IBaseFilter_Release(ds);
        ds = NULL;
    }
    if (dsin) {
        IPin_Release(dsin);
        dsin = NULL;
    }
    if (!split)
        split = find_audio_src_pin(gb);

    if (existing) {
        wo = existing;
        existing = NULL;
        wmpwo_log("reusing SS1 WaveOut already in graph\n");
        hr = S_OK;
    } else {
        hr = load_ss1_filter(&wo);
        wmpwo_log_hr("load_ss1_filter", hr);
        if (FAILED(hr) || !wo)
            goto done;
        hr = IGraphBuilder_AddFilter(gb, wo, SS1_WO_FILTER_NAME);
        wmpwo_log_hr("AddFilter SS1 WaveOut", hr);
        if (FAILED(hr))
            goto done;
    }

    woin = find_pin_dir(wo, PINDIR_INPUT, 0);
    if (!woin)
        woin = find_pin_dir(wo, PINDIR_INPUT, 1);
    if (!woin || !split) {
        wmpwo_log("FAIL pins woin=%p split=%p\n", (void *)woin, (void *)split);
        hr = E_FAIL;
        goto done;
    }
    {
        IPin *peer = NULL;
        int already = 0;
        if (SUCCEEDED(IPin_ConnectedTo(woin, &peer)) && peer) {
            already = (peer == split);
            IPin_Release(peer);
        }
        if (already) {
            wmpwo_log("SS1 WaveOut already connected to splitter\n");
            hr = S_OK;
        } else {
            hr = IGraphBuilder_ConnectDirect(gb, split, woin, NULL);
            wmpwo_log_hr("ConnectDirect splitter->SS1WaveOut", hr);
            if (FAILED(hr))
                goto done;
        }
    }

    still = find_filter_by_clsid(gb, &CLSID_DSoundRender);
    if (!still)
        still = find_filter_by_clsid(gb, &CLSID_AudioRender);
    if (still) {
        wmpwo_log("FAIL DirectSound still in graph after swap\n");
        IBaseFilter_Release(still);
        hr = E_FAIL;
        goto done;
    }
    InterlockedIncrement(&g_wmpwo_swaps);
    wmpwo_log("graph has no DirectSound renderer swaps=%ld\n", (long)g_wmpwo_swaps);
    hr = S_OK;

    if (paused && mc) {
        HRESULT hr2 = IMediaControl_Run(mc);
        wmpwo_log_hr("Run after swap", hr2);
    }

done:
    if (woin)
        IPin_Release(woin);
    if (split)
        IPin_Release(split);
    if (wo)
        IBaseFilter_Release(wo);
    if (existing)
        IBaseFilter_Release(existing);
    if (mc)
        IMediaControl_Release(mc);
    return hr;
}

static int graph_needs_swap(IGraphBuilder *gb, int *n_ds, int *n_ss1)
{
    int ds = 0, ss1 = 0, gst = 0, all = 0;
    enum_graph(gb, &ds, &ss1, &gst, &all);
    if (n_ds) *n_ds = ds;
    if (n_ss1) *n_ss1 = ss1;
    return ds > 0;
}

static HRESULT scan_rot_once(void)
{
    IRunningObjectTable *rot = NULL;
    IEnumMoniker *en = NULL;
    IMoniker *mon = NULL;
    IBindCtx *bc = NULL;
    HRESULT hr;
    int graphs = 0, swapped = 0, ok = 0, ds_left = 0;

    hr = GetRunningObjectTable(0, &rot);
    if (FAILED(hr) || !rot) {
        wmpwo_log_hr("GetRunningObjectTable", hr);
        return hr;
    }
    CreateBindCtx(0, &bc);
    hr = IRunningObjectTable_EnumRunning(rot, &en);
    if (FAILED(hr) || !en) {
        wmpwo_log_hr("EnumRunning", hr);
        IRunningObjectTable_Release(rot);
        if (bc)
            IBindCtx_Release(bc);
        return hr;
    }
    while (IEnumMoniker_Next(en, 1, &mon, NULL) == S_OK && mon) {
        LPOLESTR name = NULL;
        IUnknown *unk = NULL;
        IGraphBuilder *gb = NULL;
        WCHAR *p;

        IMoniker_GetDisplayName(mon, bc, NULL, &name);
        p = name;
        if (p && (*p == L'!' || *p == L'*'))
            p++;
        if (p && wcsstr(p, L"FilterGraph")) {
            wmpwo_log_w("ROT", name ? name : L"?");
            hr = IRunningObjectTable_GetObject(rot, mon, &unk);
            if (SUCCEEDED(hr) && unk) {
                hr = IUnknown_QueryInterface(unk, &IID_IGraphBuilder, (void **)&gb);
                wmpwo_log_hr("ROT IGraphBuilder", hr);
            }
            if (gb) {
                int ds = 0, ss1 = 0;
                DWORD cookie = (DWORD)(ULONG_PTR)gb;
                graphs++;
                if (g_wmpwo_last_graph && g_wmpwo_last_graph != cookie && ss1 == 0)
                    InterlockedIncrement(&g_wmpwo_rebuilds);
                g_wmpwo_last_graph = cookie;
                if (graph_needs_swap(gb, &ds, &ss1)) {
                    wmpwo_log("SWAP begin graph=%p ds=%d ss1=%d\n", (void *)gb, ds, ss1);
                    hr = force_ss1_on_graph(gb);
                    wmpwo_log_hr("force_ss1_on_graph", hr);
                    enum_graph(gb, &ds, &ss1, NULL, NULL);
                    if (SUCCEEDED(hr) && ds == 0 && ss1 > 0) {
                        swapped++;
                        ok++;
                    } else if (ds)
                        ds_left++;
                } else if (ss1 > 0 && ds == 0) {
                    ok++;
                    InterlockedExchange(&g_wmpwo_ss1_ok, 1);
                } else if (ds)
                    ds_left++;
                IGraphBuilder_Release(gb);
            }
            if (unk)
                IUnknown_Release(unk);
        }
        if (name)
            CoTaskMemFree(name);
        IMoniker_Release(mon);
        mon = NULL;
        if (graphs > 8)
            break;
    }
    IEnumMoniker_Release(en);
    if (bc)
        IBindCtx_Release(bc);
    IRunningObjectTable_Release(rot);
    g_wmpwo_graphs_now = (DWORD)graphs;
    if (graphs)
        wmpwo_log("SCAN graphs=%d swapped=%d ss1_ok=%d ds_left=%d rebuilds=%ld swaps=%ld\n",
                  graphs, swapped, ok, ds_left, (long)g_wmpwo_rebuilds, (long)g_wmpwo_swaps);
    if (ok && !ds_left)
        InterlockedExchange(&g_wmpwo_ss1_ok, 1);
    return S_OK;
}

#endif
