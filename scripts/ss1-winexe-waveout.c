/* Minimal DirectShow PCM renderer: IMemInputPin → WinMM waveOut*.
 * Phase 1: PCM only, no MP3, no IBasicAudio, no IReferenceClock.
 *
 * i686-w64-mingw32-gcc -O2 -shared -o ss1waveout.ax \
 *   ss1-winexe-waveout.c ss1waveout.def \
 *   -lole32 -loleaut32 -lwinmm -lstrmiids -luuid
 */
#define COBJMACROS
#define CINTERFACE
#define STRSAFE_NO_DEPRECATE
#include <windows.h>
#include <mmsystem.h>
#include <ole2.h>
#include <dshow.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <initguid.h>
#include "ss1-winexe-waveout.h"

static LONG g_objects;
static LONG g_locks;

static void logf(const char *fmt, ...)
{
    va_list ap;
    printf("SS1WO: ");
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    fflush(stdout);
}

static void log_hr(const char *label, HRESULT hr)
{
    if (hr == S_OK)
        logf("%s hr=0x%08X S_OK\n", label, (unsigned)hr);
    else if (hr == S_FALSE)
        logf("%s hr=0x%08X S_FALSE\n", label, (unsigned)hr);
    else
        logf("%s hr=0x%08X\n", label, (unsigned)hr);
}

typedef struct SS1Filter SS1Filter;

typedef struct {
    IEnumPins IEnumPins_iface;
    LONG ref;
    SS1Filter *f;
    UINT index;
} EnumPins;

typedef struct {
    IEnumMediaTypes IEnumMediaTypes_iface;
    LONG ref;
    AM_MEDIA_TYPE mt;
    int has_mt;
    UINT index;
} EnumMT;

struct SS1Filter {
    IBaseFilter IBaseFilter_iface;
    IMediaSeeking IMediaSeeking_iface;
    IAMFilterMiscFlags IAMFilterMiscFlags_iface;
    IPin IPin_iface;
    IMemInputPin IMemInputPin_iface;
    IQualityControl IQualityControl_iface;
    LONG ref;

    IFilterGraph *graph;
    IMediaEventSink *sink;
    IReferenceClock *clock;
    IMemAllocator *alloc;
    IPin *peer;
    IQualityControl *qc_sink;
    WCHAR name[128];

    FILTER_STATE state;
    BOOL flushing;
    BOOL eos;
    BOOL connected;

    AM_MEDIA_TYPE mt;
    WAVEFORMATEX fmt;

    HWAVEOUT hwo;
    WAVEHDR hdr[SS1_WO_BUFFERS];
    BYTE *buf[SS1_WO_BUFFERS];
    BOOL busy[SS1_WO_BUFFERS];
    DWORD buf_bytes;
    UINT nbufs;
    UINT device_id;
    char device_name[64];

    CRITICAL_SECTION cs;
    HANDLE free_ev;
    HANDLE drain_ev;
    LONG in_flight;
    LONG starve;
    LONG recv_count;
    LONG done_count;
    LONG bytes_written;
    BOOL eos_waiting;
    BOOL released;
    DWORD t_first_recv;
    DWORD t_first_write;
    DWORD t_release;
    LONG min_in_flight;
};

static HRESULT ss1_create(IUnknown *outer, IBaseFilter **out);

static inline SS1Filter *f_from_base(IBaseFilter *iface)
{
    return CONTAINING_RECORD(iface, SS1Filter, IBaseFilter_iface);
}
static inline SS1Filter *f_from_seek(IMediaSeeking *iface)
{
    return CONTAINING_RECORD(iface, SS1Filter, IMediaSeeking_iface);
}
static inline SS1Filter *f_from_misc(IAMFilterMiscFlags *iface)
{
    return CONTAINING_RECORD(iface, SS1Filter, IAMFilterMiscFlags_iface);
}
static inline SS1Filter *f_from_pin(IPin *iface)
{
    return CONTAINING_RECORD(iface, SS1Filter, IPin_iface);
}
static inline SS1Filter *f_from_mem(IMemInputPin *iface)
{
    return CONTAINING_RECORD(iface, SS1Filter, IMemInputPin_iface);
}
static inline SS1Filter *f_from_qc(IQualityControl *iface)
{
    return CONTAINING_RECORD(iface, SS1Filter, IQualityControl_iface);
}

static void free_mt(AM_MEDIA_TYPE *mt)
{
    if (!mt)
        return;
    if (mt->cbFormat && mt->pbFormat)
        CoTaskMemFree(mt->pbFormat);
    if (mt->pUnk)
        IUnknown_Release(mt->pUnk);
    memset(mt, 0, sizeof(*mt));
}

static HRESULT copy_mt(AM_MEDIA_TYPE *dst, const AM_MEDIA_TYPE *src)
{
    free_mt(dst);
    *dst = *src;
    dst->pbFormat = NULL;
    dst->pUnk = NULL;
    if (src->cbFormat && src->pbFormat) {
        dst->pbFormat = CoTaskMemAlloc(src->cbFormat);
        if (!dst->pbFormat) {
            memset(dst, 0, sizeof(*dst));
            return E_OUTOFMEMORY;
        }
        memcpy(dst->pbFormat, src->pbFormat, src->cbFormat);
    }
    if (src->pUnk)
        IUnknown_AddRef(src->pUnk);
    dst->pUnk = src->pUnk;
    return S_OK;
}

static void fill_default_mt(AM_MEDIA_TYPE *mt, WAVEFORMATEX *wf)
{
    memset(mt, 0, sizeof(*mt));
    memset(wf, 0, sizeof(*wf));
    wf->wFormatTag = WAVE_FORMAT_PCM;
    wf->nChannels = 2;
    wf->nSamplesPerSec = 44100;
    wf->wBitsPerSample = 16;
    wf->nBlockAlign = 4;
    wf->nAvgBytesPerSec = 44100 * 4;
    mt->majortype = MEDIATYPE_Audio;
    mt->subtype = MEDIASUBTYPE_PCM;
    mt->bFixedSizeSamples = TRUE;
    mt->lSampleSize = 4;
    mt->formattype = FORMAT_WaveFormatEx;
    mt->cbFormat = sizeof(WAVEFORMATEX);
    mt->pbFormat = CoTaskMemAlloc(sizeof(WAVEFORMATEX));
    if (mt->pbFormat)
        memcpy(mt->pbFormat, wf, sizeof(WAVEFORMATEX));
}

static HRESULT parse_pcm(const AM_MEDIA_TYPE *mt, WAVEFORMATEX *out)
{
    const WAVEFORMATEX *wf;

    if (!mt || !out)
        return E_POINTER;
    if (!IsEqualGUID(&mt->majortype, &MEDIATYPE_Audio))
        return VFW_E_TYPE_NOT_ACCEPTED;
    if (!IsEqualGUID(&mt->formattype, &FORMAT_WaveFormatEx))
        return VFW_E_TYPE_NOT_ACCEPTED;
    if (!IsEqualGUID(&mt->subtype, &MEDIASUBTYPE_PCM) &&
        !IsEqualGUID(&mt->subtype, &GUID_NULL))
        return VFW_E_TYPE_NOT_ACCEPTED;
    if (!mt->pbFormat || mt->cbFormat < sizeof(WAVEFORMATEX))
        return VFW_E_TYPE_NOT_ACCEPTED;
    wf = (const WAVEFORMATEX *)mt->pbFormat;
    if (wf->wFormatTag != WAVE_FORMAT_PCM)
        return VFW_E_TYPE_NOT_ACCEPTED;
    if (wf->nChannels < 1 || wf->nChannels > 2)
        return VFW_E_TYPE_NOT_ACCEPTED;
    if (wf->wBitsPerSample != 8 && wf->wBitsPerSample != 16)
        return VFW_E_TYPE_NOT_ACCEPTED;
    if (wf->nSamplesPerSec < 8000 || wf->nSamplesPerSec > 48000)
        return VFW_E_TYPE_NOT_ACCEPTED;
    if (!wf->nBlockAlign)
        return VFW_E_TYPE_NOT_ACCEPTED;
    *out = *wf;
    if (!out->nAvgBytesPerSec)
        out->nAvgBytesPerSec = out->nSamplesPerSec * out->nBlockAlign;
    return S_OK;
}

static void CALLBACK wo_proc(HWAVEOUT hwo, UINT msg, DWORD_PTR inst,
                             DWORD_PTR p1, DWORD_PTR p2)
{
    SS1Filter *f = (SS1Filter *)inst;
    WAVEHDR *hdr;
    UINT i;
    LONG done;

    (void)hwo;
    (void)p2;
    if (!f || msg != WOM_DONE)
        return;
    hdr = (WAVEHDR *)p1;
    EnterCriticalSection(&f->cs);
    i = (UINT)hdr->dwUser;
    if (i < f->nbufs)
        f->busy[i] = FALSE;
    if (f->in_flight > 0)
        f->in_flight--;
    done = ++f->done_count;
    if (f->released && f->in_flight < f->min_in_flight)
        f->min_in_flight = f->in_flight;
    if (f->eos_waiting && f->in_flight == 0)
        SetEvent(f->drain_ev);
    SetEvent(f->free_ev);
    {
        DWORD now = GetTickCount();
        BOOL early = !f->released ||
                     (f->t_release && (now - f->t_release) < 2000);
        LONG inflight = f->in_flight;
        LONG minfl = f->min_in_flight;
        BOOL rel = f->released;
        LeaveCriticalSection(&f->cs);

        if (!rel)
            logf("WOM_DONE_BEFORE_RELEASE n=%ld in_flight=%ld\n",
                 (long)done, (long)inflight);
        else {
            DWORD every = ((now - f->t_release) < 2000) ? 1 : 50;
            if (early || (done % every) == 0 || done <= 8)
                logf("WOM_DONE n=%ld in_flight=%ld min=%ld dt=%lu\n",
                     (long)done, (long)inflight, (long)minfl,
                     (unsigned long)(f->t_release ? now - f->t_release : 0));
        }
        return;
    }
}

static void wo_free_buffers(SS1Filter *f)
{
    UINT i;
    for (i = 0; i < SS1_WO_BUFFERS; i++) {
        if (f->buf[i]) {
            HeapFree(GetProcessHeap(), 0, f->buf[i]);
            f->buf[i] = NULL;
        }
        memset(&f->hdr[i], 0, sizeof(f->hdr[i]));
        f->busy[i] = FALSE;
    }
}

static void wo_close(SS1Filter *f)
{
    UINT i;

    if (!f->hwo)
        return;
    logf("waveOutReset/close in_flight=%ld\n", (long)f->in_flight);
    waveOutReset(f->hwo);
    WaitForSingleObject(f->drain_ev, 50);
    {
        DWORD t0 = GetTickCount();
        while (f->in_flight > 0 && (GetTickCount() - t0) < 2000)
            WaitForSingleObject(f->free_ev, 50);
    }
    for (i = 0; i < f->nbufs; i++) {
        if (f->hdr[i].lpData)
            waveOutUnprepareHeader(f->hwo, &f->hdr[i], sizeof(WAVEHDR));
    }
    waveOutClose(f->hwo);
    f->hwo = NULL;
    wo_free_buffers(f);
    f->in_flight = 0;
    f->nbufs = 0;
}

static HRESULT wo_open(SS1Filter *f, const WAVEFORMATEX *wf)
{
    MMRESULT mmr;
    UINT i, samples;
    WAVEOUTCAPS caps;
    WAVEFORMATEX fmt;

    wo_close(f);
    fmt = *wf;
    f->fmt = fmt;
    f->nbufs = SS1_WO_BUFFERS;
    samples = (UINT)((fmt.nSamplesPerSec * SS1_WO_BUFFER_MS) / 1000);
    if (samples < 1)
        samples = 1;
    f->buf_bytes = samples * fmt.nBlockAlign;

    mmr = waveOutOpen(&f->hwo, WAVE_MAPPER, &fmt, (DWORD_PTR)wo_proc,
                      (DWORD_PTR)f, CALLBACK_FUNCTION);
    logf("waveOutOpen mmr=%u device=WAVE_MAPPER ch=%u rate=%lu bits=%u "
         "block=%u avg=%lu buffers=%u buffer_ms=%u bytes=%lu total_ms=%u\n",
         mmr, fmt.nChannels, (unsigned long)fmt.nSamplesPerSec,
         fmt.wBitsPerSample, fmt.nBlockAlign,
         (unsigned long)fmt.nAvgBytesPerSec, f->nbufs, SS1_WO_BUFFER_MS,
         (unsigned long)f->buf_bytes, f->nbufs * SS1_WO_BUFFER_MS);
    if (mmr != MMSYSERR_NOERROR) {
        mmr = waveOutOpen(&f->hwo, 0, &fmt, (DWORD_PTR)wo_proc,
                          (DWORD_PTR)f, CALLBACK_FUNCTION);
        logf("waveOutOpen retry device=0 mmr=%u\n", mmr);
    }
    if (mmr != MMSYSERR_NOERROR) {
        f->hwo = NULL;
        return HRESULT_FROM_WIN32(mmr);
    }

    f->device_id = (UINT)-1;
    waveOutGetID(f->hwo, &f->device_id);
    memset(&caps, 0, sizeof caps);
    if (waveOutGetDevCaps(f->device_id == (UINT)-1 ? WAVE_MAPPER : f->device_id,
                          &caps, sizeof caps) == MMSYSERR_NOERROR) {
#ifdef UNICODE
        WideCharToMultiByte(CP_ACP, 0, caps.szPname, -1,
                            f->device_name, (int)sizeof f->device_name, NULL, NULL);
#else
        lstrcpynA(f->device_name, caps.szPname, (int)sizeof f->device_name);
#endif
        logf("waveOut device_id=%u name=%s\n", f->device_id, f->device_name);
    } else {
        logf("waveOut device_id=%u name=(unknown)\n", f->device_id);
    }

    for (i = 0; i < f->nbufs; i++) {
        f->buf[i] = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, f->buf_bytes);
        if (!f->buf[i]) {
            wo_close(f);
            return E_OUTOFMEMORY;
        }
        memset(&f->hdr[i], 0, sizeof(f->hdr[i]));
        f->hdr[i].lpData = (LPSTR)f->buf[i];
        f->hdr[i].dwBufferLength = f->buf_bytes;
        f->hdr[i].dwUser = i;
        mmr = waveOutPrepareHeader(f->hwo, &f->hdr[i], sizeof(WAVEHDR));
        if (mmr != MMSYSERR_NOERROR) {
            logf("waveOutPrepareHeader[%u] mmr=%u\n", i, mmr);
            wo_close(f);
            return HRESULT_FROM_WIN32(mmr);
        }
        f->busy[i] = FALSE;
    }
    f->in_flight = 0;
    f->done_count = 0;
    f->bytes_written = 0;
    f->released = FALSE;
    f->t_first_recv = 0;
    f->t_first_write = 0;
    f->t_release = 0;
    f->min_in_flight = 0;
    ResetEvent(f->drain_ev);
    SetEvent(f->free_ev);
    /* Stay paused until try_release() sees in_flight >= SS1_WO_PRIME_BUFFERS. */
    waveOutPause(f->hwo);
    logf("waveOut paused; will release at in_flight>=%d (~%d ms)\n",
         SS1_WO_PRIME_BUFFERS, SS1_WO_PRIME_BUFFERS * SS1_WO_BUFFER_MS);
    return S_OK;
}

static int wait_free(SS1Filter *f, DWORD timeout)
{
    DWORD start = GetTickCount();
    for (;;) {
        UINT i;
        EnterCriticalSection(&f->cs);
        if (f->flushing || f->state == State_Stopped || f->eos) {
            LeaveCriticalSection(&f->cs);
            return -2;
        }
        for (i = 0; i < f->nbufs; i++) {
            if (!f->busy[i]) {
                f->busy[i] = TRUE;
                LeaveCriticalSection(&f->cs);
                return (int)i;
            }
        }
        LeaveCriticalSection(&f->cs);
        if (timeout != INFINITE && (GetTickCount() - start) >= timeout)
            return -1;
        WaitForSingleObject(f->free_ev, timeout == INFINITE ? 100 : 50);
    }
}

static void try_release(SS1Filter *f)
{
    LONG q = 0;
    BOOL do_it = FALSE;
    BOOL eos = FALSE;

    if (!f->hwo)
        return;
    EnterCriticalSection(&f->cs);
    if (f->state == State_Running && !f->released) {
        if (f->in_flight >= SS1_WO_PRIME_BUFFERS || f->eos) {
            do_it = TRUE;
            f->released = TRUE;
            q = f->in_flight;
            eos = f->eos;
            f->t_release = GetTickCount();
            f->min_in_flight = q;
        }
    }
    LeaveCriticalSection(&f->cs);
    if (!do_it)
        return;
    waveOutRestart(f->hwo);
    logf("playback released in_flight=%ld prime=%d dt_recv_ms=%lu dt_write_ms=%lu%s\n",
         (long)q, SS1_WO_PRIME_BUFFERS,
         (unsigned long)(f->t_first_recv ? f->t_release - f->t_first_recv : 0),
         (unsigned long)(f->t_first_write ? f->t_release - f->t_first_write : 0),
         eos ? " (EOS fallback)" : "");
}

static HRESULT write_pcm(SS1Filter *f, const BYTE *data, DWORD len)
{
    while (len) {
        int idx;
        DWORD chunk;
        MMRESULT mmr;

        idx = wait_free(f, 2000);
        if (idx == -1) {
            InterlockedIncrement(&f->starve);
            logf("STARVE waiting for WAVEHDR recv=%ld in_flight=%ld starve=%ld\n",
                 (long)f->recv_count, (long)f->in_flight, (long)f->starve);
            idx = wait_free(f, INFINITE);
        }
        if (idx < 0)
            return S_FALSE;

        chunk = len;
        if (chunk > f->buf_bytes)
            chunk = f->buf_bytes;
        memcpy(f->buf[idx], data, chunk);
        f->hdr[idx].dwBufferLength = chunk;
        f->hdr[idx].dwFlags &= ~(WHDR_DONE | WHDR_INQUEUE);
        f->hdr[idx].dwFlags |= WHDR_PREPARED;

        if (!f->t_first_write) {
            f->t_first_write = GetTickCount();
            logf("first waveOutWrite tick=%lu len=%lu in_flight=%ld\n",
                 (unsigned long)f->t_first_write, (unsigned long)chunk,
                 (long)f->in_flight);
        }
        mmr = waveOutWrite(f->hwo, &f->hdr[idx], sizeof(WAVEHDR));
        if (mmr != MMSYSERR_NOERROR) {
            logf("waveOutWrite mmr=%u idx=%d len=%lu\n", mmr, idx, (unsigned long)chunk);
            EnterCriticalSection(&f->cs);
            f->busy[idx] = FALSE;
            SetEvent(f->free_ev);
            LeaveCriticalSection(&f->cs);
            return HRESULT_FROM_WIN32(mmr);
        }
        EnterCriticalSection(&f->cs);
        f->in_flight++;
        f->bytes_written += (LONG)chunk;
        LeaveCriticalSection(&f->cs);
        try_release(f);
        data += chunk;
        len -= chunk;
    }
    return S_OK;
}

/* ---------- IUnknown / IBaseFilter ---------- */

static HRESULT WINAPI base_QI(IBaseFilter *iface, REFIID riid, void **ppv)
{
    SS1Filter *f = f_from_base(iface);
    if (!ppv)
        return E_POINTER;
    *ppv = NULL;
    if (IsEqualGUID(riid, &IID_IUnknown) ||
        IsEqualGUID(riid, &IID_IPersist) ||
        IsEqualGUID(riid, &IID_IMediaFilter) ||
        IsEqualGUID(riid, &IID_IBaseFilter))
        *ppv = &f->IBaseFilter_iface;
    else if (IsEqualGUID(riid, &IID_IMediaSeeking))
        *ppv = &f->IMediaSeeking_iface;
    else if (IsEqualGUID(riid, &IID_IAMFilterMiscFlags))
        *ppv = &f->IAMFilterMiscFlags_iface;
    else
        return E_NOINTERFACE;
    IBaseFilter_AddRef(&f->IBaseFilter_iface);
    return S_OK;
}

static ULONG WINAPI base_AddRef(IBaseFilter *iface)
{
    SS1Filter *f = f_from_base(iface);
    return InterlockedIncrement(&f->ref);
}

static ULONG WINAPI base_Release(IBaseFilter *iface)
{
    SS1Filter *f = f_from_base(iface);
    ULONG r = InterlockedDecrement(&f->ref);
    if (!r) {
        wo_close(f);
        free_mt(&f->mt);
        if (f->peer) {
            IPin_Release(f->peer);
            f->peer = NULL;
        }
        if (f->alloc) {
            IMemAllocator_Release(f->alloc);
            f->alloc = NULL;
        }
        if (f->clock) {
            IReferenceClock_Release(f->clock);
            f->clock = NULL;
        }
        if (f->sink) {
            IMediaEventSink_Release(f->sink);
            f->sink = NULL;
        }
        if (f->graph) {
            IFilterGraph_Release(f->graph);
            f->graph = NULL;
        }
        if (f->qc_sink) {
            IQualityControl_Release(f->qc_sink);
            f->qc_sink = NULL;
        }
        if (f->free_ev)
            CloseHandle(f->free_ev);
        if (f->drain_ev)
            CloseHandle(f->drain_ev);
        DeleteCriticalSection(&f->cs);
        HeapFree(GetProcessHeap(), 0, f);
        InterlockedDecrement(&g_objects);
    }
    return r;
}

static HRESULT WINAPI base_GetClassID(IBaseFilter *iface, CLSID *id)
{
    if (!id)
        return E_POINTER;
    *id = CLSID_SS1WaveOut;
    (void)iface;
    return S_OK;
}

static HRESULT WINAPI base_Stop(IBaseFilter *iface)
{
    SS1Filter *f = f_from_base(iface);
    logf("Stop\n");
    EnterCriticalSection(&f->cs);
    f->state = State_Stopped;
    f->eos_waiting = FALSE;
    f->released = FALSE;
    SetEvent(f->free_ev);
    SetEvent(f->drain_ev);
    LeaveCriticalSection(&f->cs);
    if (f->hwo)
        waveOutReset(f->hwo);
    if (f->alloc)
        IMemAllocator_Decommit(f->alloc);
    return S_OK;
}

static HRESULT WINAPI base_Pause(IBaseFilter *iface)
{
    SS1Filter *f = f_from_base(iface);
    logf("Pause from %d\n", (int)f->state);
    EnterCriticalSection(&f->cs);
    if (f->state == State_Running && f->hwo)
        waveOutPause(f->hwo);
    f->state = State_Paused;
    LeaveCriticalSection(&f->cs);
    if (f->alloc)
        IMemAllocator_Commit(f->alloc);
    return S_OK;
}

static HRESULT WINAPI base_Run(IBaseFilter *iface, REFERENCE_TIME start)
{
    SS1Filter *f = f_from_base(iface);
    logf("Run start=%lld hwo=%p in_flight=%ld released=%d (hold until prime=%d)\n",
         (long long)start, (void *)f->hwo, (long)f->in_flight, (int)f->released,
         SS1_WO_PRIME_BUFFERS);
    (void)start;
    EnterCriticalSection(&f->cs);
    f->state = State_Running;
    LeaveCriticalSection(&f->cs);
    if (f->hwo && f->released)
        waveOutRestart(f->hwo);
    else
        try_release(f);
    if (f->alloc)
        IMemAllocator_Commit(f->alloc);
    return S_OK;
}

static HRESULT WINAPI base_GetState(IBaseFilter *iface, DWORD ms, FILTER_STATE *st)
{
    SS1Filter *f = f_from_base(iface);
    (void)ms;
    if (!st)
        return E_POINTER;
    *st = f->state;
    return S_OK;
}

static HRESULT WINAPI base_SetSyncSource(IBaseFilter *iface, IReferenceClock *c)
{
    SS1Filter *f = f_from_base(iface);
    if (f->clock)
        IReferenceClock_Release(f->clock);
    f->clock = c;
    if (f->clock)
        IReferenceClock_AddRef(f->clock);
    logf("SetSyncSource clock=%p (unused for pacing; waveOut paces)\n", (void *)c);
    return S_OK;
}

static HRESULT WINAPI base_GetSyncSource(IBaseFilter *iface, IReferenceClock **c)
{
    SS1Filter *f = f_from_base(iface);
    if (!c)
        return E_POINTER;
    *c = f->clock;
    if (*c)
        IReferenceClock_AddRef(*c);
    return S_OK;
}

static HRESULT enum_pins_new(SS1Filter *f, UINT index, IEnumPins **out);

static HRESULT WINAPI base_EnumPins2(IBaseFilter *iface, IEnumPins **en)
{
    SS1Filter *f = f_from_base(iface);
    if (!en)
        return E_POINTER;
    return enum_pins_new(f, 0, en);
}

static HRESULT WINAPI base_FindPin(IBaseFilter *iface, LPCWSTR id, IPin **pin)
{
    SS1Filter *f = f_from_base(iface);
    if (!pin)
        return E_POINTER;
    *pin = NULL;
    if (id && (lstrcmpiW(id, SS1_WO_PIN_ID) == 0 || lstrcmpiW(id, SS1_WO_PIN_NAME) == 0)) {
        *pin = &f->IPin_iface;
        IPin_AddRef(*pin);
        return S_OK;
    }
    return VFW_E_NOT_FOUND;
}

static HRESULT WINAPI base_QueryFilterInfo(IBaseFilter *iface, FILTER_INFO *info)
{
    SS1Filter *f = f_from_base(iface);
    if (!info)
        return E_POINTER;
    lstrcpynW(info->achName, f->name[0] ? f->name : SS1_WO_FILTER_NAME, MAX_FILTER_NAME);
    info->pGraph = f->graph;
    if (info->pGraph)
        IFilterGraph_AddRef(info->pGraph);
    return S_OK;
}

static HRESULT WINAPI base_JoinFilterGraph(IBaseFilter *iface, IFilterGraph *g, LPCWSTR name)
{
    SS1Filter *f = f_from_base(iface);
    if (f->sink) {
        IMediaEventSink_Release(f->sink);
        f->sink = NULL;
    }
    if (f->graph) {
        IFilterGraph_Release(f->graph);
        f->graph = NULL;
    }
    f->graph = g;
    if (f->graph) {
        IFilterGraph_AddRef(f->graph);
        IFilterGraph_QueryInterface(f->graph, &IID_IMediaEventSink, (void **)&f->sink);
    }
    if (name)
        lstrcpynW(f->name, name, 128);
    logf("JoinFilterGraph graph=%p name set\n", (void *)g);
    return S_OK;
}

static HRESULT WINAPI base_QueryVendorInfo(IBaseFilter *iface, LPWSTR *info)
{
    (void)iface;
    if (!info)
        return E_POINTER;
    *info = NULL;
    return E_NOTIMPL;
}

static const IBaseFilterVtbl base_vtbl = {
    base_QI,
    base_AddRef,
    base_Release,
    base_GetClassID,
    base_Stop,
    base_Pause,
    base_Run,
    base_GetState,
    base_SetSyncSource,
    base_GetSyncSource,
    base_EnumPins2,
    base_FindPin,
    base_QueryFilterInfo,
    base_JoinFilterGraph,
    base_QueryVendorInfo
};

/* ---------- IAMFilterMiscFlags ---------- */

static HRESULT WINAPI misc_QI(IAMFilterMiscFlags *iface, REFIID riid, void **ppv)
{
    return IBaseFilter_QueryInterface(&f_from_misc(iface)->IBaseFilter_iface, riid, ppv);
}
static ULONG WINAPI misc_AddRef(IAMFilterMiscFlags *iface)
{
    return IBaseFilter_AddRef(&f_from_misc(iface)->IBaseFilter_iface);
}
static ULONG WINAPI misc_Release(IAMFilterMiscFlags *iface)
{
    return IBaseFilter_Release(&f_from_misc(iface)->IBaseFilter_iface);
}
static ULONG WINAPI misc_GetMiscFlags(IAMFilterMiscFlags *iface)
{
    (void)iface;
    return AM_FILTER_MISC_FLAGS_IS_RENDERER;
}
static const IAMFilterMiscFlagsVtbl misc_vtbl = {
    misc_QI, misc_AddRef, misc_Release, misc_GetMiscFlags
};

/* ---------- IMediaSeeking (position only) ---------- */

static HRESULT WINAPI seek_QI(IMediaSeeking *iface, REFIID riid, void **ppv)
{
    return IBaseFilter_QueryInterface(&f_from_seek(iface)->IBaseFilter_iface, riid, ppv);
}
static ULONG WINAPI seek_AddRef(IMediaSeeking *iface)
{
    return IBaseFilter_AddRef(&f_from_seek(iface)->IBaseFilter_iface);
}
static ULONG WINAPI seek_Release(IMediaSeeking *iface)
{
    return IBaseFilter_Release(&f_from_seek(iface)->IBaseFilter_iface);
}
static HRESULT WINAPI seek_GetCaps(IMediaSeeking *iface, DWORD *p)
{
    (void)iface;
    if (!p)
        return E_POINTER;
    *p = AM_SEEKING_CanGetCurrentPos;
    return S_OK;
}
static HRESULT WINAPI seek_CheckCaps(IMediaSeeking *iface, DWORD *p)
{
    DWORD cap = 0;
    seek_GetCaps(iface, &cap);
    if (!p)
        return E_POINTER;
    *p &= cap;
    return S_OK;
}
static HRESULT WINAPI seek_IsFmt(IMediaSeeking *iface, const GUID *fmt)
{
    (void)iface;
    return (fmt && IsEqualGUID(fmt, &TIME_FORMAT_MEDIA_TIME)) ? S_OK : S_FALSE;
}
static HRESULT WINAPI seek_QueryPref(IMediaSeeking *iface, GUID *fmt)
{
    (void)iface;
    if (!fmt)
        return E_POINTER;
    *fmt = TIME_FORMAT_MEDIA_TIME;
    return S_OK;
}
static HRESULT WINAPI seek_GetTimeFmt(IMediaSeeking *iface, GUID *fmt)
{
    return seek_QueryPref(iface, fmt);
}
static HRESULT WINAPI seek_IsUsing(IMediaSeeking *iface, const GUID *fmt)
{
    return seek_IsFmt(iface, fmt);
}
static HRESULT WINAPI seek_SetTimeFmt(IMediaSeeking *iface, const GUID *fmt)
{
    (void)iface;
    return (fmt && IsEqualGUID(fmt, &TIME_FORMAT_MEDIA_TIME)) ? S_OK : E_INVALIDARG;
}
static HRESULT WINAPI seek_GetDur(IMediaSeeking *iface, LONGLONG *p)
{
    (void)iface;
    if (!p)
        return E_POINTER;
    *p = 0;
    return E_NOTIMPL;
}
static HRESULT WINAPI seek_GetStop(IMediaSeeking *iface, LONGLONG *p)
{
    return seek_GetDur(iface, p);
}
static HRESULT WINAPI seek_GetPos(IMediaSeeking *iface, LONGLONG *p)
{
    SS1Filter *f = f_from_seek(iface);
    MMTIME mmt;
    if (!p)
        return E_POINTER;
    *p = 0;
    if (!f->hwo || !f->fmt.nAvgBytesPerSec)
        return S_OK;
    memset(&mmt, 0, sizeof mmt);
    mmt.wType = TIME_BYTES;
    if (waveOutGetPosition(f->hwo, &mmt, sizeof mmt) == MMSYSERR_NOERROR &&
        mmt.wType == TIME_BYTES)
        *p = ((LONGLONG)mmt.u.cb * 10000000LL) / f->fmt.nAvgBytesPerSec;
    else
        *p = ((LONGLONG)f->bytes_written * 10000000LL) / f->fmt.nAvgBytesPerSec;
    return S_OK;
}
static HRESULT WINAPI seek_Convert(IMediaSeeking *iface, const GUID *sin, LONGLONG tin,
                                   const GUID *sout, LONGLONG *tout)
{
    (void)iface;
    if (!tout)
        return E_POINTER;
    if (sin && sout && IsEqualGUID(sin, sout)) {
        *tout = tin;
        return S_OK;
    }
    return E_NOTIMPL;
}
static HRESULT WINAPI seek_SetPos(IMediaSeeking *iface, LONGLONG *c, DWORD cf, LONGLONG *s, DWORD sf)
{
    (void)iface;
    (void)c;
    (void)cf;
    (void)s;
    (void)sf;
    return E_NOTIMPL;
}
static HRESULT WINAPI seek_GetPositions(IMediaSeeking *iface, LONGLONG *c, LONGLONG *s)
{
    if (c)
        seek_GetPos(iface, c);
    if (s)
        *s = 0;
    return S_OK;
}
static HRESULT WINAPI seek_GetAvail(IMediaSeeking *iface, LONGLONG *earliest, LONGLONG *latest)
{
    (void)iface;
    if (earliest)
        *earliest = 0;
    if (latest)
        *latest = 0;
    return E_NOTIMPL;
}
static HRESULT WINAPI seek_SetRate(IMediaSeeking *iface, double r)
{
    (void)iface;
    return (r == 1.0) ? S_OK : E_NOTIMPL;
}
static HRESULT WINAPI seek_GetRate(IMediaSeeking *iface, double *r)
{
    (void)iface;
    if (!r)
        return E_POINTER;
    *r = 1.0;
    return S_OK;
}
static HRESULT WINAPI seek_GetPreroll(IMediaSeeking *iface, LONGLONG *p)
{
    (void)iface;
    if (!p)
        return E_POINTER;
    *p = 0;
    return S_OK;
}
static const IMediaSeekingVtbl seek_vtbl = {
    seek_QI, seek_AddRef, seek_Release,
    seek_GetCaps, seek_CheckCaps, seek_IsFmt, seek_QueryPref, seek_GetTimeFmt,
    seek_IsUsing, seek_SetTimeFmt, seek_GetDur, seek_GetStop, seek_GetPos,
    seek_Convert, seek_SetPos, seek_GetPositions, seek_GetAvail,
    seek_SetRate, seek_GetRate, seek_GetPreroll
};

/* ---------- IEnumPins ---------- */

static HRESULT WINAPI ep_QI(IEnumPins *iface, REFIID riid, void **ppv)
{
    EnumPins *e = CONTAINING_RECORD(iface, EnumPins, IEnumPins_iface);
    if (!ppv)
        return E_POINTER;
    if (IsEqualGUID(riid, &IID_IUnknown) || IsEqualGUID(riid, &IID_IEnumPins)) {
        *ppv = &e->IEnumPins_iface;
        InterlockedIncrement(&e->ref);
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI ep_AddRef(IEnumPins *iface)
{
    EnumPins *e = CONTAINING_RECORD(iface, EnumPins, IEnumPins_iface);
    return InterlockedIncrement(&e->ref);
}
static ULONG WINAPI ep_Release(IEnumPins *iface)
{
    EnumPins *e = CONTAINING_RECORD(iface, EnumPins, IEnumPins_iface);
    ULONG r = InterlockedDecrement(&e->ref);
    if (!r) {
        IBaseFilter_Release(&e->f->IBaseFilter_iface);
        HeapFree(GetProcessHeap(), 0, e);
    }
    return r;
}
static HRESULT WINAPI ep_Next(IEnumPins *iface, ULONG c, IPin **pins, ULONG *fetched)
{
    EnumPins *e = CONTAINING_RECORD(iface, EnumPins, IEnumPins_iface);
    ULONG n = 0;
    if (!pins)
        return E_POINTER;
    if (fetched)
        *fetched = 0;
    if (c == 0)
        return E_INVALIDARG;
    if (e->index == 0 && c >= 1) {
        pins[0] = &e->f->IPin_iface;
        IPin_AddRef(pins[0]);
        e->index = 1;
        n = 1;
    }
    if (fetched)
        *fetched = n;
    return (n == c) ? S_OK : S_FALSE;
}
static HRESULT WINAPI ep_Skip(IEnumPins *iface, ULONG c)
{
    EnumPins *e = CONTAINING_RECORD(iface, EnumPins, IEnumPins_iface);
    e->index += c;
    return (e->index > 1) ? S_FALSE : S_OK;
}
static HRESULT WINAPI ep_Reset(IEnumPins *iface)
{
    EnumPins *e = CONTAINING_RECORD(iface, EnumPins, IEnumPins_iface);
    e->index = 0;
    return S_OK;
}
static HRESULT WINAPI ep_Clone(IEnumPins *iface, IEnumPins **out)
{
    EnumPins *e = CONTAINING_RECORD(iface, EnumPins, IEnumPins_iface);
    return enum_pins_new(e->f, e->index, out);
}
static const IEnumPinsVtbl enum_pins_vtbl_real = {
    ep_QI, ep_AddRef, ep_Release, ep_Next, ep_Skip, ep_Reset, ep_Clone
};
static HRESULT enum_pins_new(SS1Filter *f, UINT index, IEnumPins **out)
{
    EnumPins *e;
    if (!out)
        return E_POINTER;
    e = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*e));
    if (!e)
        return E_OUTOFMEMORY;
    e->IEnumPins_iface.lpVtbl = &enum_pins_vtbl_real;
    e->ref = 1;
    e->f = f;
    e->index = index;
    IBaseFilter_AddRef(&f->IBaseFilter_iface);
    *out = &e->IEnumPins_iface;
    return S_OK;
}

/* ---------- IEnumMediaTypes ---------- */

static HRESULT WINAPI em_QI(IEnumMediaTypes *iface, REFIID riid, void **ppv)
{
    EnumMT *e = CONTAINING_RECORD(iface, EnumMT, IEnumMediaTypes_iface);
    if (!ppv)
        return E_POINTER;
    if (IsEqualGUID(riid, &IID_IUnknown) || IsEqualGUID(riid, &IID_IEnumMediaTypes)) {
        *ppv = iface;
        InterlockedIncrement(&e->ref);
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI em_AddRef(IEnumMediaTypes *iface)
{
    EnumMT *e = CONTAINING_RECORD(iface, EnumMT, IEnumMediaTypes_iface);
    return InterlockedIncrement(&e->ref);
}
static ULONG WINAPI em_Release(IEnumMediaTypes *iface)
{
    EnumMT *e = CONTAINING_RECORD(iface, EnumMT, IEnumMediaTypes_iface);
    ULONG r = InterlockedDecrement(&e->ref);
    if (!r) {
        free_mt(&e->mt);
        HeapFree(GetProcessHeap(), 0, e);
    }
    return r;
}
static HRESULT WINAPI em_Next(IEnumMediaTypes *iface, ULONG c, AM_MEDIA_TYPE **out, ULONG *fetched)
{
    EnumMT *e = CONTAINING_RECORD(iface, EnumMT, IEnumMediaTypes_iface);
    ULONG n = 0;
    if (!out)
        return E_POINTER;
    if (fetched)
        *fetched = 0;
    if (e->has_mt && e->index == 0 && c >= 1) {
        out[0] = CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE));
        if (!out[0])
            return E_OUTOFMEMORY;
        memset(out[0], 0, sizeof(AM_MEDIA_TYPE));
        if (FAILED(copy_mt(out[0], &e->mt))) {
            CoTaskMemFree(out[0]);
            return E_OUTOFMEMORY;
        }
        e->index = 1;
        n = 1;
    }
    if (fetched)
        *fetched = n;
    return (n == c) ? S_OK : S_FALSE;
}
static HRESULT WINAPI em_Skip(IEnumMediaTypes *iface, ULONG c)
{
    EnumMT *e = CONTAINING_RECORD(iface, EnumMT, IEnumMediaTypes_iface);
    e->index += c;
    return S_FALSE;
}
static HRESULT WINAPI em_Reset(IEnumMediaTypes *iface)
{
    EnumMT *e = CONTAINING_RECORD(iface, EnumMT, IEnumMediaTypes_iface);
    e->index = 0;
    return S_OK;
}
static HRESULT WINAPI em_Clone(IEnumMediaTypes *iface, IEnumMediaTypes **out)
{
    (void)iface;
    if (out)
        *out = NULL;
    return E_NOTIMPL;
}
static const IEnumMediaTypesVtbl enum_mt_vtbl = {
    em_QI, em_AddRef, em_Release, em_Next, em_Skip, em_Reset, em_Clone
};

static HRESULT enum_mt_new(const AM_MEDIA_TYPE *src, IEnumMediaTypes **out)
{
    EnumMT *e;
    WAVEFORMATEX wf;
    if (!out)
        return E_POINTER;
    e = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*e));
    if (!e)
        return E_OUTOFMEMORY;
    e->IEnumMediaTypes_iface.lpVtbl = &enum_mt_vtbl;
    e->ref = 1;
    if (src && src->pbFormat)
        copy_mt(&e->mt, src);
    else
        fill_default_mt(&e->mt, &wf);
    e->has_mt = e->mt.pbFormat != NULL;
    *out = &e->IEnumMediaTypes_iface;
    return S_OK;
}

/* ---------- IPin ---------- */

static HRESULT WINAPI pin_QI(IPin *iface, REFIID riid, void **ppv)
{
    SS1Filter *f = f_from_pin(iface);
    if (!ppv)
        return E_POINTER;
    *ppv = NULL;
    if (IsEqualGUID(riid, &IID_IUnknown) || IsEqualGUID(riid, &IID_IPin))
        *ppv = &f->IPin_iface;
    else if (IsEqualGUID(riid, &IID_IMemInputPin))
        *ppv = &f->IMemInputPin_iface;
    else if (IsEqualGUID(riid, &IID_IQualityControl))
        *ppv = &f->IQualityControl_iface;
    else
        return E_NOINTERFACE;
    IPin_AddRef(&f->IPin_iface);
    return S_OK;
}
static ULONG WINAPI pin_AddRef(IPin *iface)
{
    return IBaseFilter_AddRef(&f_from_pin(iface)->IBaseFilter_iface);
}
static ULONG WINAPI pin_Release(IPin *iface)
{
    return IBaseFilter_Release(&f_from_pin(iface)->IBaseFilter_iface);
}
static HRESULT WINAPI pin_Connect(IPin *iface, IPin *p, const AM_MEDIA_TYPE *mt)
{
    (void)iface;
    (void)p;
    (void)mt;
    return E_UNEXPECTED;
}
static HRESULT WINAPI pin_QueryAccept(IPin *iface, const AM_MEDIA_TYPE *mt)
{
    WAVEFORMATEX wf;
    HRESULT hr = parse_pcm(mt, &wf);
    (void)iface;
    return FAILED(hr) ? S_FALSE : S_OK;
}
static HRESULT WINAPI pin_ReceiveConnection(IPin *iface, IPin *connector, const AM_MEDIA_TYPE *mt)
{
    SS1Filter *f = f_from_pin(iface);
    WAVEFORMATEX wf;
    HRESULT hr;

    if (!connector || !mt)
        return E_POINTER;
    if (f->connected)
        return VFW_E_ALREADY_CONNECTED;
    hr = parse_pcm(mt, &wf);
    if (FAILED(hr)) {
        log_hr("ReceiveConnection parse_pcm", hr);
        return VFW_E_TYPE_NOT_ACCEPTED;
    }
    hr = copy_mt(&f->mt, mt);
    if (FAILED(hr))
        return hr;
    hr = wo_open(f, &wf);
    log_hr("ReceiveConnection wo_open", hr);
    if (FAILED(hr)) {
        free_mt(&f->mt);
        return hr;
    }
    f->peer = connector;
    IPin_AddRef(f->peer);
    f->connected = TRUE;
    f->eos = FALSE;
    f->flushing = FALSE;
    return S_OK;
}
static HRESULT WINAPI pin_Disconnect(IPin *iface)
{
    SS1Filter *f = f_from_pin(iface);
    if (!f->connected)
        return S_FALSE;
    if (f->state != State_Stopped)
        return VFW_E_NOT_STOPPED;
    wo_close(f);
    if (f->peer) {
        IPin_Release(f->peer);
        f->peer = NULL;
    }
    free_mt(&f->mt);
    f->connected = FALSE;
    logf("Disconnect\n");
    return S_OK;
}
static HRESULT WINAPI pin_ConnectedTo(IPin *iface, IPin **pin)
{
    SS1Filter *f = f_from_pin(iface);
    if (!pin)
        return E_POINTER;
    *pin = f->peer;
    if (!*pin)
        return VFW_E_NOT_CONNECTED;
    IPin_AddRef(*pin);
    return S_OK;
}
static HRESULT WINAPI pin_ConnectionMediaType(IPin *iface, AM_MEDIA_TYPE *mt)
{
    SS1Filter *f = f_from_pin(iface);
    if (!mt)
        return E_POINTER;
    if (!f->connected)
        return VFW_E_NOT_CONNECTED;
    memset(mt, 0, sizeof(*mt));
    return copy_mt(mt, &f->mt);
}
static HRESULT WINAPI pin_QueryPinInfo(IPin *iface, PIN_INFO *info)
{
    SS1Filter *f = f_from_pin(iface);
    if (!info)
        return E_POINTER;
    info->pFilter = &f->IBaseFilter_iface;
    IBaseFilter_AddRef(info->pFilter);
    info->dir = PINDIR_INPUT;
    lstrcpynW(info->achName, SS1_WO_PIN_NAME, MAX_PIN_NAME);
    return S_OK;
}
static HRESULT WINAPI pin_QueryDirection(IPin *iface, PIN_DIRECTION *dir)
{
    (void)iface;
    if (!dir)
        return E_POINTER;
    *dir = PINDIR_INPUT;
    return S_OK;
}
static HRESULT WINAPI pin_QueryId(IPin *iface, LPWSTR *id)
{
    (void)iface;
    if (!id)
        return E_POINTER;
    *id = CoTaskMemAlloc((lstrlenW(SS1_WO_PIN_ID) + 1) * sizeof(WCHAR));
    if (!*id)
        return E_OUTOFMEMORY;
    lstrcpyW(*id, SS1_WO_PIN_ID);
    return S_OK;
}
static HRESULT WINAPI pin_EnumMediaTypes(IPin *iface, IEnumMediaTypes **en)
{
    SS1Filter *f = f_from_pin(iface);
    return enum_mt_new(f->connected ? &f->mt : NULL, en);
}
static HRESULT WINAPI pin_QueryInternal(IPin *iface, IPin ***pins, ULONG *n)
{
    (void)iface;
    if (pins)
        *pins = NULL;
    if (n)
        *n = 0;
    return E_NOTIMPL;
}
static HRESULT WINAPI pin_EndOfStream(IPin *iface)
{
    SS1Filter *f = f_from_pin(iface);
    DWORD wait_ms;

    logf("EndOfStream in_flight=%ld bytes=%ld starve=%ld recv=%ld done=%ld\n",
         (long)f->in_flight, (long)f->bytes_written, (long)f->starve,
         (long)f->recv_count, (long)f->done_count);
    EnterCriticalSection(&f->cs);
    if (f->flushing) {
        LeaveCriticalSection(&f->cs);
        return S_FALSE;
    }
    f->eos = TRUE;
    f->eos_waiting = TRUE;
    if (f->in_flight == 0)
        SetEvent(f->drain_ev);
    LeaveCriticalSection(&f->cs);
    try_release(f);

    wait_ms = (DWORD)(f->nbufs * SS1_WO_BUFFER_MS * 4 + 2000);
    WaitForSingleObject(f->drain_ev, wait_ms);
    logf("EOS drained in_flight=%ld done=%ld starve=%ld min_in_flight=%ld released=%d\n",
         (long)f->in_flight, (long)f->done_count, (long)f->starve,
         (long)f->min_in_flight, (int)f->released);

    if (f->sink && f->state != State_Stopped) {
        HRESULT hr = IMediaEventSink_Notify(f->sink, EC_COMPLETE, S_OK,
                                            (LONG_PTR)&f->IBaseFilter_iface);
        log_hr("EC_COMPLETE Notify", hr);
    }
    return S_OK;
}
static HRESULT WINAPI pin_BeginFlush(IPin *iface)
{
    SS1Filter *f = f_from_pin(iface);
    logf("BeginFlush\n");
    EnterCriticalSection(&f->cs);
    f->flushing = TRUE;
    f->eos = FALSE;
    f->eos_waiting = FALSE;
    f->released = FALSE;
    SetEvent(f->free_ev);
    SetEvent(f->drain_ev);
    LeaveCriticalSection(&f->cs);
    if (f->hwo)
        waveOutReset(f->hwo);
    return S_OK;
}
static HRESULT WINAPI pin_EndFlush(IPin *iface)
{
    SS1Filter *f = f_from_pin(iface);
    logf("EndFlush\n");
    EnterCriticalSection(&f->cs);
    f->flushing = FALSE;
    ResetEvent(f->drain_ev);
    LeaveCriticalSection(&f->cs);
    if (f->hwo)
        waveOutPause(f->hwo);
    return S_OK;
}
static HRESULT WINAPI pin_NewSegment(IPin *iface, REFERENCE_TIME a, REFERENCE_TIME b, double r)
{
    (void)iface;
    logf("NewSegment tStart=%lld tStop=%lld rate=%g\n",
         (long long)a, (long long)b, r);
    return S_OK;
}

static const IPinVtbl pin_vtbl = {
    pin_QI, pin_AddRef, pin_Release,
    pin_Connect, pin_ReceiveConnection, pin_Disconnect,
    pin_ConnectedTo, pin_ConnectionMediaType, pin_QueryPinInfo,
    pin_QueryDirection, pin_QueryId, pin_QueryAccept, pin_EnumMediaTypes,
    pin_QueryInternal, pin_EndOfStream, pin_BeginFlush, pin_EndFlush, pin_NewSegment
};

/* ---------- IMemInputPin ---------- */

static HRESULT WINAPI mem_QI(IMemInputPin *iface, REFIID riid, void **ppv)
{
    return IPin_QueryInterface(&f_from_mem(iface)->IPin_iface, riid, ppv);
}
static ULONG WINAPI mem_AddRef(IMemInputPin *iface)
{
    return IPin_AddRef(&f_from_mem(iface)->IPin_iface);
}
static ULONG WINAPI mem_Release(IMemInputPin *iface)
{
    return IPin_Release(&f_from_mem(iface)->IPin_iface);
}
static HRESULT WINAPI mem_GetAllocator(IMemInputPin *iface, IMemAllocator **alloc)
{
    SS1Filter *f = f_from_mem(iface);
    HRESULT hr;
    if (!alloc)
        return E_POINTER;
    if (!f->alloc) {
        hr = CoCreateInstance(&CLSID_MemoryAllocator, NULL, CLSCTX_INPROC_SERVER,
                              &IID_IMemAllocator, (void **)&f->alloc);
        if (FAILED(hr))
            return VFW_E_NO_ALLOCATOR;
    }
    *alloc = f->alloc;
    IMemAllocator_AddRef(*alloc);
    return S_OK;
}
static HRESULT WINAPI mem_NotifyAllocator(IMemInputPin *iface, IMemAllocator *alloc, BOOL readonly)
{
    SS1Filter *f = f_from_mem(iface);
    (void)readonly;
    if (!alloc)
        return E_POINTER;
    if (f->alloc)
        IMemAllocator_Release(f->alloc);
    f->alloc = alloc;
    IMemAllocator_AddRef(f->alloc);
    return S_OK;
}
static HRESULT WINAPI mem_GetAllocatorRequirements(IMemInputPin *iface, ALLOCATOR_PROPERTIES *p)
{
    SS1Filter *f = f_from_mem(iface);
    if (!p)
        return E_POINTER;
    p->cBuffers = SS1_WO_BUFFERS;
    p->cbBuffer = f->buf_bytes ? (long)f->buf_bytes : 4096;
    p->cbAlign = 1;
    p->cbPrefix = 0;
    return S_OK;
}
static HRESULT WINAPI mem_Receive(IMemInputPin *iface, IMediaSample *sample)
{
    SS1Filter *f = f_from_mem(iface);
    BYTE *ptr = NULL;
    LONG slen;
    HRESULT hr;

    if (!sample)
        return E_POINTER;
    if (f->flushing || f->eos)
        return S_FALSE;
    if (f->state == State_Stopped)
        return VFW_E_WRONG_STATE;
    if (!f->hwo)
        return VFW_E_NOT_CONNECTED;

    slen = IMediaSample_GetActualDataLength(sample);
    hr = IMediaSample_GetPointer(sample, &ptr);
    if (FAILED(hr) || !ptr)
        return FAILED(hr) ? hr : E_POINTER;
    if (slen <= 0)
        return S_OK;

    f->recv_count++;
    if (f->recv_count == 1) {
        f->t_first_recv = GetTickCount();
        logf("first Receive tick=%lu len=%ld in_flight=%ld state=%d released=%d\n",
             (unsigned long)f->t_first_recv, (long)slen, (long)f->in_flight,
             (int)f->state, (int)f->released);
    }
    if (f->recv_count <= 8 || (f->recv_count % 50) == 0)
        logf("Receive n=%ld len=%ld in_flight=%ld released=%d\n",
             (long)f->recv_count, (long)slen, (long)f->in_flight, (int)f->released);

    return write_pcm(f, ptr, (DWORD)slen);
}
static HRESULT WINAPI mem_ReceiveMultiple(IMemInputPin *iface, IMediaSample **arr, long n, long *proc)
{
    long i, done = 0;
    HRESULT hr = S_OK;
    if (proc)
        *proc = 0;
    if (!arr)
        return E_POINTER;
    for (i = 0; i < n; i++) {
        hr = mem_Receive(iface, arr[i]);
        if (hr != S_OK)
            break;
        done++;
    }
    if (proc)
        *proc = done;
    return hr;
}
static HRESULT WINAPI mem_ReceiveCanBlock(IMemInputPin *iface)
{
    (void)iface;
    return S_OK;
}
static const IMemInputPinVtbl mem_vtbl = {
    mem_QI, mem_AddRef, mem_Release,
    mem_GetAllocator, mem_NotifyAllocator, mem_GetAllocatorRequirements,
    mem_Receive, mem_ReceiveMultiple, mem_ReceiveCanBlock
};

/* ---------- IQualityControl ---------- */

static HRESULT WINAPI qc_QI(IQualityControl *iface, REFIID riid, void **ppv)
{
    return IPin_QueryInterface(&f_from_qc(iface)->IPin_iface, riid, ppv);
}
static ULONG WINAPI qc_AddRef(IQualityControl *iface)
{
    return IPin_AddRef(&f_from_qc(iface)->IPin_iface);
}
static ULONG WINAPI qc_Release(IQualityControl *iface)
{
    return IPin_Release(&f_from_qc(iface)->IPin_iface);
}
static HRESULT WINAPI qc_Notify(IQualityControl *iface, IBaseFilter *self, Quality q)
{
    (void)iface;
    (void)self;
    (void)q;
    return S_OK;
}
static HRESULT WINAPI qc_SetSink(IQualityControl *iface, IQualityControl *sink)
{
    SS1Filter *f = f_from_qc(iface);
    if (f->qc_sink)
        IQualityControl_Release(f->qc_sink);
    f->qc_sink = sink;
    if (f->qc_sink)
        IQualityControl_AddRef(f->qc_sink);
    return S_OK;
}
static const IQualityControlVtbl qc_vtbl = {
    qc_QI, qc_AddRef, qc_Release, qc_Notify, qc_SetSink
};

/* ---------- create / class factory / DLL ---------- */

static HRESULT ss1_create(IUnknown *outer, IBaseFilter **out)
{
    SS1Filter *f;
    if (outer)
        return CLASS_E_NOAGGREGATION;
    if (!out)
        return E_POINTER;
    f = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*f));
    if (!f)
        return E_OUTOFMEMORY;
    f->IBaseFilter_iface.lpVtbl = &base_vtbl;
    f->IMediaSeeking_iface.lpVtbl = &seek_vtbl;
    f->IAMFilterMiscFlags_iface.lpVtbl = &misc_vtbl;
    f->IPin_iface.lpVtbl = &pin_vtbl;
    f->IMemInputPin_iface.lpVtbl = &mem_vtbl;
    f->IQualityControl_iface.lpVtbl = &qc_vtbl;
    f->ref = 1;
    f->state = State_Stopped;
    lstrcpyW(f->name, SS1_WO_FILTER_NAME);
    InitializeCriticalSection(&f->cs);
    f->free_ev = CreateEventW(NULL, FALSE, TRUE, NULL);
    f->drain_ev = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!f->free_ev || !f->drain_ev) {
        if (f->free_ev)
            CloseHandle(f->free_ev);
        if (f->drain_ev)
            CloseHandle(f->drain_ev);
        DeleteCriticalSection(&f->cs);
        HeapFree(GetProcessHeap(), 0, f);
        return E_OUTOFMEMORY;
    }
    InterlockedIncrement(&g_objects);
    logf("created buffers=%d buffer_ms=%d total_ms=%d clsid={B7E3C101-5A42-4D8F-9C1E-A1B2C3D4E5F6}\n",
         SS1_WO_BUFFERS, SS1_WO_BUFFER_MS, SS1_WO_BUFFERS * SS1_WO_BUFFER_MS);
    *out = &f->IBaseFilter_iface;
    return S_OK;
}

typedef struct {
    IClassFactory IClassFactory_iface;
    LONG ref;
} SS1CF;

static HRESULT WINAPI cf_QI(IClassFactory *iface, REFIID riid, void **ppv)
{
    SS1CF *c = CONTAINING_RECORD(iface, SS1CF, IClassFactory_iface);
    if (!ppv)
        return E_POINTER;
    if (IsEqualGUID(riid, &IID_IUnknown) || IsEqualGUID(riid, &IID_IClassFactory)) {
        *ppv = &c->IClassFactory_iface;
        InterlockedIncrement(&c->ref);
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}
static ULONG WINAPI cf_AddRef(IClassFactory *iface)
{
    SS1CF *c = CONTAINING_RECORD(iface, SS1CF, IClassFactory_iface);
    return InterlockedIncrement(&c->ref);
}
static ULONG WINAPI cf_Release(IClassFactory *iface)
{
    SS1CF *c = CONTAINING_RECORD(iface, SS1CF, IClassFactory_iface);
    ULONG r = InterlockedDecrement(&c->ref);
    if (!r)
        HeapFree(GetProcessHeap(), 0, c);
    return r;
}
static HRESULT WINAPI cf_Create(IClassFactory *iface, IUnknown *outer, REFIID riid, void **ppv)
{
    IBaseFilter *flt = NULL;
    HRESULT hr;
    (void)iface;
    if (!ppv)
        return E_POINTER;
    *ppv = NULL;
    hr = ss1_create(outer, &flt);
    if (FAILED(hr))
        return hr;
    hr = IBaseFilter_QueryInterface(flt, riid, ppv);
    IBaseFilter_Release(flt);
    return hr;
}
static HRESULT WINAPI cf_Lock(IClassFactory *iface, BOOL lock)
{
    (void)iface;
    if (lock)
        InterlockedIncrement(&g_locks);
    else
        InterlockedDecrement(&g_locks);
    return S_OK;
}
static const IClassFactoryVtbl cf_vtbl = {
    cf_QI, cf_AddRef, cf_Release, cf_Create, cf_Lock
};

#ifdef __GNUC__
#define SS1_EXPORT __attribute__((dllexport))
#else
#define SS1_EXPORT __declspec(dllexport)
#endif

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *res)
{
    (void)res;
    if (reason == DLL_PROCESS_ATTACH)
        DisableThreadLibraryCalls(inst);
    return TRUE;
}

SS1_EXPORT HRESULT WINAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void **ppv)
{
    SS1CF *c;
    if (!ppv)
        return E_POINTER;
    *ppv = NULL;
    if (!IsEqualGUID(rclsid, &CLSID_SS1WaveOut))
        return CLASS_E_CLASSNOTAVAILABLE;
    c = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*c));
    if (!c)
        return E_OUTOFMEMORY;
    c->IClassFactory_iface.lpVtbl = &cf_vtbl;
    c->ref = 1;
    {
        HRESULT hr = IClassFactory_QueryInterface(&c->IClassFactory_iface, riid, ppv);
        IClassFactory_Release(&c->IClassFactory_iface);
        return hr;
    }
}

SS1_EXPORT HRESULT WINAPI DllCanUnloadNow(void)
{
    return (g_objects || g_locks) ? S_FALSE : S_OK;
}

SS1_EXPORT HRESULT WINAPI DllRegisterServer(void)
{
    /* Phase 1: harness loads via DllGetClassObject. Do not register globally. */
    return S_OK;
}

SS1_EXPORT HRESULT WINAPI DllUnregisterServer(void)
{
    return S_OK;
}
