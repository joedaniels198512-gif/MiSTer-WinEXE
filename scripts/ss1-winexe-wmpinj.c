/* WMP-process-only DirectShow graph interceptor.
 * Loaded into wmplayer.exe (CreateRemoteThread LoadLibrary). Does not
 * replace CLSID_DSoundRender globally and does not change filter merits.
 *
 * i686-w64-mingw32-gcc -O2 -shared -o ss1wmpinj.dll \
 *   ss1-winexe-wmpinj.c ss1wmpinj.def \
 *   -Wl,--kill-at -static-libgcc -lole32 -loleaut32 -lstrmiids -luuid
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define CINTERFACE
#define STRSAFE_NO_DEPRECATE
#include <windows.h>
#include <ole2.h>
#include <dshow.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <wchar.h>
#include <initguid.h>
#include "ss1-winexe-waveout.h"
#include "ss1-winexe-wmpwo-graph.c"

static HANDLE g_thread;
static HANDLE g_stop;
static volatile LONG g_started;

static DWORD WINAPI watch_thread(LPVOID unused)
{
    HRESULT hr;
    DWORD n = 0;
    MSG msg;

    (void)unused;
    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    wmpwo_log_hr("inj CoInitializeEx", hr);
    if (FAILED(hr) && hr != S_FALSE)
        return 1;
    wmpwo_log("inj watcher pid=%lu tid=%lu\n",
              (unsigned long)GetCurrentProcessId(),
              (unsigned long)GetCurrentThreadId());
    InterlockedExchange(&g_started, 1);

    for (;;) {
        if (WaitForSingleObject(g_stop, 0) == WAIT_OBJECT_0)
            break;
        scan_rot_once();
        n++;
        if ((n % 50) == 1)
            wmpwo_log("inj heartbeat n=%lu ss1_ok=%ld swaps=%ld ds_seen=%ld graphs=%lu rebuilds=%ld\n",
                      (unsigned long)n, (long)g_wmpwo_ss1_ok, (long)g_wmpwo_swaps,
                      (long)g_wmpwo_dsound_seen, (unsigned long)g_wmpwo_graphs_now,
                      (long)g_wmpwo_rebuilds);
        /* STA message pump so marshalled graph calls can run. */
        {
            DWORD t0 = GetTickCount();
            while (GetTickCount() - t0 < 80) {
                while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
                MsgWaitForMultipleObjects(1, &g_stop, FALSE, 20, QS_ALLINPUT);
                if (WaitForSingleObject(g_stop, 0) == WAIT_OBJECT_0)
                    goto out;
            }
        }
    }
out:
    wmpwo_log("inj watcher exit swaps=%ld ss1_ok=%ld\n",
              (long)g_wmpwo_swaps, (long)g_wmpwo_ss1_ok);
    CoUninitialize();
    return 0;
}

#ifdef __GNUC__
#define SS1_EXPORT __attribute__((dllexport))
#else
#define SS1_EXPORT __declspec(dllexport)
#endif

SS1_EXPORT HRESULT WINAPI Ss1WmpInjStart(void)
{
    if (InterlockedCompareExchange(&g_started, 0, 0) && g_thread)
        return S_FALSE;
    if (!g_stop)
        g_stop = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!g_thread)
        g_thread = CreateThread(NULL, 0, watch_thread, NULL, 0, NULL);
    return g_thread ? S_OK : E_FAIL;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *res)
{
    WCHAR exe[MAX_PATH];
    const WCHAR *base;

    (void)res;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        exe[0] = 0;
        GetModuleFileNameW(NULL, exe, MAX_PATH);
        base = wcsrchr(exe, L'\\');
        base = base ? base + 1 : exe;
        /* Only act inside genuine WMP. Harmless if a helper loads us. */
        if (lstrcmpiW(base, L"wmplayer.exe") != 0 &&
            lstrcmpiW(base, L"WMPLAYER.EXE") != 0) {
            return TRUE;
        }
        g_stop = CreateEventW(NULL, TRUE, FALSE, NULL);
        g_thread = CreateThread(NULL, 0, watch_thread, NULL, 0, NULL);
    } else if (reason == DLL_PROCESS_DETACH) {
        if (g_stop)
            SetEvent(g_stop);
        if (g_thread) {
            WaitForSingleObject(g_thread, 500);
            CloseHandle(g_thread);
            g_thread = NULL;
        }
        if (g_stop) {
            CloseHandle(g_stop);
            g_stop = NULL;
        }
        if (g_wmpwo_file) {
            fclose(g_wmpwo_file);
            g_wmpwo_file = NULL;
        }
    }
    return TRUE;
}
