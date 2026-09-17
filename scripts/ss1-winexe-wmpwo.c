/* WMP-only helper: inject ss1wmpinj.dll into wmplayer.exe and/or
 * rewrite FilterGraph instances on the ROT. Same wineserver session.
 *
 * i686-w64-mingw32-gcc -O2 -o ss1-winexe-wmpwo.exe ss1-winexe-wmpwo.c \
 *   -static-libgcc -lole32 -loleaut32 -lstrmiids -luuid
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define CINTERFACE
#define STRSAFE_NO_DEPRECATE
#include <windows.h>
#include <tlhelp32.h>
#include <ole2.h>
#include <dshow.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <initguid.h>
#include "ss1-winexe-waveout.h"
#include "ss1-winexe-wmpwo-graph.c"

static DWORD find_wmplayer(void)
{
    HANDLE snap;
    PROCESSENTRY32W pe;
    DWORD pid = 0;

    snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE)
        return 0;
    pe.dwSize = sizeof pe;
    if (Process32FirstW(snap, &pe)) {
        do {
            if (lstrcmpiW(pe.szExeFile, L"wmplayer.exe") == 0) {
                pid = pe.th32ProcessID;
                break;
            }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return pid;
}

static int module_loaded(DWORD pid, const WCHAR *want)
{
    HANDLE snap;
    MODULEENTRY32W me;
    int found = 0;

    snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snap == INVALID_HANDLE_VALUE)
        return 0;
    me.dwSize = sizeof me;
    if (Module32FirstW(snap, &me)) {
        do {
            if (lstrcmpiW(me.szModule, want) == 0) {
                found = 1;
                break;
            }
        } while (Module32NextW(snap, &me));
    }
    CloseHandle(snap);
    return found;
}

static HRESULT inject_dll(DWORD pid, const WCHAR *path)
{
    HANDLE proc = NULL, thr = NULL;
    void *remote = NULL;
    SIZE_T nbytes, wrote = 0;
    HMODULE k32;
    LPTHREAD_START_ROUTINE loadw;
    DWORD wait, exitc = 0;

    nbytes = (lstrlenW(path) + 1) * sizeof(WCHAR);
    proc = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
                       PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ,
                       FALSE, pid);
    if (!proc) {
        wmpwo_log("OpenProcess pid=%lu gle=%lu\n",
                  (unsigned long)pid, (unsigned long)GetLastError());
        return HRESULT_FROM_WIN32(GetLastError());
    }
    k32 = GetModuleHandleW(L"kernel32.dll");
    loadw = (LPTHREAD_START_ROUTINE)GetProcAddress(k32, "LoadLibraryW");
    if (!loadw) {
        CloseHandle(proc);
        return E_FAIL;
    }
    remote = VirtualAllocEx(proc, NULL, nbytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remote) {
        wmpwo_log("VirtualAllocEx gle=%lu\n", (unsigned long)GetLastError());
        CloseHandle(proc);
        return E_OUTOFMEMORY;
    }
    if (!WriteProcessMemory(proc, remote, path, nbytes, &wrote)) {
        wmpwo_log("WriteProcessMemory gle=%lu\n", (unsigned long)GetLastError());
        VirtualFreeEx(proc, remote, 0, MEM_RELEASE);
        CloseHandle(proc);
        return HRESULT_FROM_WIN32(GetLastError());
    }
    thr = CreateRemoteThread(proc, NULL, 0, loadw, remote, 0, NULL);
    if (!thr) {
        wmpwo_log("CreateRemoteThread gle=%lu\n", (unsigned long)GetLastError());
        VirtualFreeEx(proc, remote, 0, MEM_RELEASE);
        CloseHandle(proc);
        return HRESULT_FROM_WIN32(GetLastError());
    }
    wait = WaitForSingleObject(thr, 8000);
    GetExitCodeThread(thr, &exitc);
    wmpwo_log("inject wait=%lu LoadLibraryW exit=%lu (0=fail)\n",
              (unsigned long)wait, (unsigned long)exitc);
    CloseHandle(thr);
    VirtualFreeEx(proc, remote, 0, MEM_RELEASE);
    CloseHandle(proc);
    if (wait != WAIT_OBJECT_0 || exitc == 0)
        return E_FAIL;
    return S_OK;
}

static void stage_hint(void)
{
    WCHAR exe[MAX_PATH];
    GetModuleFileNameW(NULL, exe, MAX_PATH);
    wmpwo_log_w("helper exe", exe);
}

int main(void)
{
    HRESULT hr;
    DWORD pid = 0, t0, n = 0;
    int injected = 0;
    const WCHAR *dllpath = L"C:\\windows\\system32\\ss1wmpinj.dll";

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    wmpwo_log_hr("helper CoInitializeEx", hr);
    if (FAILED(hr) && hr != S_FALSE)
        return 2;
    stage_hint();
    t0 = GetTickCount();
    wmpwo_log("waiting for wmplayer.exe (method A: in-process graph swap)\n");
    while (GetTickCount() - t0 < 90000) {
        pid = find_wmplayer();
        if (pid)
            break;
        Sleep(50);
    }
    if (!pid) {
        wmpwo_log("FAIL no wmplayer.exe\n");
        CoUninitialize();
        return 3;
    }
    wmpwo_log("wmplayer pid=%lu\n", (unsigned long)pid);

    if (GetFileAttributesW(dllpath) == INVALID_FILE_ATTRIBUTES)
        dllpath = L"C:\\ss1wmpinj.dll";
    if (GetFileAttributesW(dllpath) == INVALID_FILE_ATTRIBUTES)
        wmpwo_log("WARN ss1wmpinj.dll missing, ROT-only fallback\n");
    else {
        hr = inject_dll(pid, dllpath);
        wmpwo_log_hr("inject_dll", hr);
        Sleep(200);
        injected = module_loaded(pid, L"ss1wmpinj.dll");
        wmpwo_log("ss1wmpinj.dll loaded=%d\n", injected);
        if (FAILED(hr) || !injected)
            wmpwo_log("inject failed — helper will try ROT swap from this process\n");
    }

    /* Keep scanning ROT. If inject worked this is backup; if not, this is A. */
    for (;;) {
        MSG msg;
        scan_rot_once();
        n++;
        if ((n % 20) == 1)
            wmpwo_log("helper heartbeat n=%lu inj=%d ss1_ok=%ld swaps=%ld ds_seen=%ld graphs=%lu rebuilds=%ld\n",
                      (unsigned long)n, injected, (long)g_wmpwo_ss1_ok,
                      (long)g_wmpwo_swaps, (long)g_wmpwo_dsound_seen,
                      (unsigned long)g_wmpwo_graphs_now, (long)g_wmpwo_rebuilds);
        if (!find_wmplayer()) {
            wmpwo_log("wmplayer exited n=%lu ss1_ok=%ld swaps=%ld\n",
                      (unsigned long)n, (long)g_wmpwo_ss1_ok, (long)g_wmpwo_swaps);
            break;
        }
        {
            DWORD t1 = GetTickCount();
            while (GetTickCount() - t1 < 100) {
                while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
                Sleep(20);
            }
        }
    }
    CoUninitialize();
    return 0;
}
