/* Tiny Win32 COM CoCreate diagnostic for WinEXE WMP9.
 * Compile: i686-w64-mingw32-gcc -o ss1-winexe-cocreate.exe ss1-winexe-cocreate.c -lole32 -luuid
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <ole2.h>
#include <stdio.h>

static void print_hr(const char *label, HRESULT hr)
{
    unsigned u = (unsigned)hr;
    if (hr == S_OK)
        printf("%s hr=0x%08X S_OK\n", label, u);
    else
        printf("%s hr=0x%08X\n", label, u);
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

int main(void)
{
    HRESULT hr, rc = S_OK;

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    print_hr("CoInitializeEx", hr);
    if (FAILED(hr) && hr != S_FALSE)
        return 2;

    /* Wave Parser */
    hr = try_clsid("WaveParser", L"{D51BD5A1-7548-11CF-A520-0080C77EF58A}");
    if (FAILED(hr))
        rc = hr;

    /* Filter Graph Manager */
    hr = try_clsid("FilterGraph", L"{E436EBB3-524F-11CE-9F53-0020AF0BA770}");
    if (FAILED(hr) && rc == S_OK)
        rc = hr;

    /* GStreamer splitter (winegstreamer) */
    hr = try_clsid("GStreamerSplitter", L"{EDDB3536-724F-41CE-A664-5471699CE629}");
    (void)hr;

    CoUninitialize();
    return FAILED(rc) ? 1 : 0;
}
