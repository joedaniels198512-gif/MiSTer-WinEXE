/*
 * Tiny PE32 focus observer / optional activator for the Wine ss1 desktop.
 * Does not modify C&C. No visible window (avoids stealing focus in observe mode).
 *
 *   ss1-cnc-focus.exe           poll GetForegroundWindow / GetActiveWindow / GetFocus
 *   ss1-cnc-focus.exe activate  SetForegroundWindow on the C&C main HWND when it appears
 *
 * i686-w64-mingw32-gcc -O2 -Wall -s -o ss1-cnc-focus.exe ss1-cnc-focus.c -static-libgcc -luser32
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

static FILE *g_log;
static int g_activate;
static HWND g_activated;
static DWORD g_t0;

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

static void describe(const char *tag, HWND hwnd)
{
    char title[256], cls[128], path[260];
    DWORD pid = 0, tid = 0;
    RECT r;
    HANDLE proc;
    DWORD n;
    DWORD style, ex;

    if (!hwnd) {
        flog("%s hwnd=0", tag);
        return;
    }
    title[0] = cls[0] = path[0] = 0;
    GetWindowTextA(hwnd, title, sizeof title);
    GetClassNameA(hwnd, cls, sizeof cls);
    tid = GetWindowThreadProcessId(hwnd, &pid);
    GetWindowRect(hwnd, &r);
    style = (DWORD)GetWindowLongA(hwnd, GWL_STYLE);
    ex = (DWORD)GetWindowLongA(hwnd, GWL_EXSTYLE);
    proc = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (proc) {
        n = sizeof path;
        if (!QueryFullProcessImageNameA(proc, 0, path, &n))
            path[0] = 0;
        CloseHandle(proc);
    }
    flog("%s hwnd=%p pid=%lu tid=%lu %dx%d style=0x%08lx ex=0x%08lx class='%s' title='%s' exe='%s'",
         tag, (void *)hwnd, (unsigned long)pid, (unsigned long)tid,
         (int)(r.right - r.left), (int)(r.bottom - r.top),
         (unsigned long)style, (unsigned long)ex, cls, title, path);
}

static HWND find_cnc_main(void)
{
    HWND best = 0;
    HWND hwnd = GetTopWindow(GetDesktopWindow());
    int best_area = 0;
    while (hwnd) {
        char title[256], cls[128];
        RECT r;
        int w, h, area;
        title[0] = cls[0] = 0;
        if (IsWindowVisible(hwnd)) {
            GetWindowTextA(hwnd, title, sizeof title);
            GetClassNameA(hwnd, cls, sizeof cls);
            GetWindowRect(hwnd, &r);
            w = r.right - r.left;
            h = r.bottom - r.top;
            area = w * h;
            if (area >= 640 * 350 &&
                (strstr(title, "Command & Conquer") ||
                 strstr(cls, "C&C") || strstr(cls, "C&C95") ||
                 strstr(cls, "c&c") || strstr(cls, "C95"))) {
                if (area > best_area) {
                    best = hwnd;
                    best_area = area;
                }
            }
        }
        hwnd = GetWindow(hwnd, GW_HWNDNEXT);
    }
    return best;
}

static void snapshot(const char *why)
{
    HWND fg = GetForegroundWindow();
    HWND active = GetActiveWindow();
    HWND focus = GetFocus();
    HWND cnc = find_cnc_main();
    flog("snap %s", why);
    describe("foreground", fg);
    describe("active", active);
    describe("focus", focus);
    describe("cnc_main", cnc);
    if (cnc)
        flog("C&C_ACTIVE=%s fg_is_cnc=%s",
             (fg == cnc) ? "YES" : "NO",
             (fg == cnc) ? "YES" : "NO");
    else
        flog("C&C_ACTIVE=NO (main hwnd not found)");
}

static void CALLBACK winevent(HWINEVENTHOOK hook, DWORD event, HWND hwnd,
                              LONG idObject, LONG idChild, DWORD thread, DWORD time)
{
    (void)hook;
    (void)idObject;
    (void)idChild;
    (void)thread;
    (void)time;
    if (event == EVENT_SYSTEM_FOREGROUND)
        describe("EVENT_SYSTEM_FOREGROUND", hwnd);
    else if (event == EVENT_OBJECT_FOCUS && idObject == OBJID_CLIENT)
        describe("EVENT_OBJECT_FOCUS", hwnd);
}

static int try_activate(HWND hwnd)
{
    HWND fg;
    DWORD fg_tid, our_tid;
    BOOL ok;
    if (!hwnd || !IsWindow(hwnd))
        return 0;
    fg = GetForegroundWindow();
    fg_tid = fg ? GetWindowThreadProcessId(fg, NULL) : 0;
    our_tid = GetCurrentThreadId();
    if (fg_tid && fg_tid != our_tid)
        AttachThreadInput(our_tid, fg_tid, TRUE);
    ShowWindow(hwnd, SW_SHOW);
    BringWindowToTop(hwnd);
    ok = SetForegroundWindow(hwnd);
    SetActiveWindow(hwnd);
    SetFocus(hwnd);
    if (fg_tid && fg_tid != our_tid)
        AttachThreadInput(our_tid, fg_tid, FALSE);
    flog("activate hwnd=%p SetForegroundWindow=%d now_fg=%p",
         (void *)hwnd, (int)ok, (void *)GetForegroundWindow());
    describe("after_activate_fg", GetForegroundWindow());
    return GetForegroundWindow() == hwnd;
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    HWINEVENTHOOK hook;
    DWORD last_snap = 0;
    char path[260];
    (void)inst;
    (void)prev;
    (void)show;
    g_t0 = GetTickCount();
    g_activate = (cmd && strstr(cmd, "activate")) ? 1 : 0;
    GetTempPathA(sizeof path, path);
    /* Prefer a unix-visible path on this Wine prefix. */
    g_log = fopen("Z:\\tmp\\ss1-cnc-focus.log", "w");
    if (!g_log)
        g_log = fopen("ss1-cnc-focus.log", "w");
    if (g_log)
        setvbuf(g_log, NULL, _IONBF, 0);
    flog("focus-probe start activate=%d pid=%lu tid=%lu cmd='%s'",
         g_activate, (unsigned long)GetCurrentProcessId(),
         (unsigned long)GetCurrentThreadId(), cmd ? cmd : "");
    hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
                           NULL, winevent, 0, 0,
                           WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    snapshot("boot");
    while (GetTickCount() - g_t0 < 25000) {
        MSG msg;
        HWND cnc;
        while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        if (g_activate) {
            cnc = find_cnc_main();
            if (cnc && cnc != g_activated) {
                describe("found_cnc", cnc);
                if (try_activate(cnc))
                    g_activated = cnc;
            } else if (cnc && GetForegroundWindow() != cnc) {
                try_activate(cnc);
            }
        }
        if (GetTickCount() - last_snap >= 200) {
            snapshot("poll");
            last_snap = GetTickCount();
        }
        Sleep(30);
    }
    snapshot("end");
    if (hook)
        UnhookWinEvent(hook);
    if (g_log)
        fclose(g_log);
    return 0;
}
