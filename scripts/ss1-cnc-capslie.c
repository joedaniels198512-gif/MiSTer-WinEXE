/*
 * One-shot in-memory debugger stub for stock C&C95.EXE (disk unchanged):
 *  - after primary/back-buffer GetCaps: clear SYSTEMMEMORY, set VIDEOMEMORY
 *  - at Get_Vert_Blank (RVA 0xDD550): xor eax,eax; ret  (skip IN 0x3DA)
 *
 * i686-w64-mingw32-gcc -O2 -Wall -s -mwindows -o ss1-cnc-capslie.exe \
 *     ss1-cnc-capslie.c -static-libgcc -lpsapi
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

#define SYS  0x00000800u
#define VID  0x00004000u

static FILE *g_log;
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

static DWORD find_pid(const char *exe)
{
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    PROCESSENTRY32 pe;
    DWORD pid = 0;
    if (snap == INVALID_HANDLE_VALUE)
        return 0;
    pe.dwSize = sizeof pe;
    if (Process32First(snap, &pe)) {
        do {
            if (lstrcmpiA(pe.szExeFile, exe) == 0) {
                pid = pe.th32ProcessID;
                break;
            }
        } while (Process32Next(snap, &pe));
    }
    CloseHandle(snap);
    return pid;
}

static DWORD_PTR module_base(DWORD pid, const char *exe)
{
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    MODULEENTRY32 me;
    DWORD_PTR base = 0;
    if (snap == INVALID_HANDLE_VALUE)
        return 0;
    me.dwSize = sizeof me;
    if (Module32First(snap, &me)) {
        do {
            if (lstrcmpiA(me.szModule, exe) == 0) {
                base = (DWORD_PTR)me.modBaseAddr;
                break;
            }
        } while (Module32Next(snap, &me));
    }
    CloseHandle(snap);
    return base;
}

static int read_ok(HANDLE hp, DWORD_PTR addr, const unsigned char *sig, SIZE_T n)
{
    unsigned char buf[16];
    SIZE_T got = 0;
    if (n > sizeof buf)
        return 0;
    if (!ReadProcessMemory(hp, (void *)addr, buf, n, &got) || got != n)
        return 0;
    return memcmp(buf, sig, n) == 0;
}

static int write_all(HANDLE hp, DWORD_PTR addr, const void *p, SIZE_T n)
{
    SIZE_T got = 0;
    DWORD old = 0, tmp;
    if (!VirtualProtectEx(hp, (void *)addr, n, PAGE_EXECUTE_READWRITE, &old))
        flog("VirtualProtectEx 0x%lx failed %lu", (unsigned long)addr, (unsigned long)GetLastError());
    if (!WriteProcessMemory(hp, (void *)addr, p, n, &got) || got != n) {
        flog("WriteProcessMemory 0x%lx failed %lu", (unsigned long)addr, (unsigned long)GetLastError());
        return 0;
    }
    VirtualProtectEx(hp, (void *)addr, n, old, &tmp);
    return 1;
}

/* Cave: rewrite [ebp+56] dwCaps, then replay original test + branch. */
static int plant(HANDLE hp, DWORD_PTR site, DWORD_PTR cave,
                 const unsigned char *orig, SIZE_T orig_n,
                 DWORD_PTR je_target, DWORD_PTR fallthrough)
{
    unsigned char code[32];
    unsigned char jmp[16];
    int n = 0;
    DWORD rel;
    unsigned i;

    /* and dword [ebp+0x56], ~SYS */
    code[n++] = 0x81; code[n++] = 0x65; code[n++] = 0x56;
    code[n++] = 0xFF; code[n++] = 0xF7; code[n++] = 0xFF; code[n++] = 0xFF;
    /* or dword [ebp+0x56], VID */
    code[n++] = 0x81; code[n++] = 0x4D; code[n++] = 0x56;
    code[n++] = 0x00; code[n++] = 0x40; code[n++] = 0x00; code[n++] = 0x00;
    /* original test byte [ebp+0x57], 08h */
    code[n++] = 0xF6; code[n++] = 0x45; code[n++] = 0x57; code[n++] = 0x08;
    /* je je_target */
    code[n++] = 0x0F; code[n++] = 0x84;
    rel = (DWORD)(je_target - (cave + n + 4));
    memcpy(code + n, &rel, 4); n += 4;
    /* jmp fallthrough */
    code[n++] = 0xE9;
    rel = (DWORD)(fallthrough - (cave + n + 4));
    memcpy(code + n, &rel, 4); n += 4;

    if (!write_all(hp, cave, code, (SIZE_T)n))
        return 0;

    memset(jmp, 0x90, sizeof jmp);
    jmp[0] = 0xE9;
    rel = (DWORD)(cave - (site + 5));
    memcpy(jmp + 1, &rel, 4);
    if (orig_n < 5)
        return 0;
    for (i = 5; i < orig_n; i++)
        jmp[i] = 0x90;
    if (!write_all(hp, site, jmp, orig_n))
        return 0;

    flog("planted site=0x%lx cave=0x%lx orig_n=%u je=0x%lx fall=0x%lx",
         (unsigned long)site, (unsigned long)cave, (unsigned)orig_n,
         (unsigned long)je_target, (unsigned long)fallthrough);
    (void)orig;
    return 1;
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    DWORD t0wait;
    DWORD pid = 0;
    HANDLE hp;
    DWORD_PTR base, cave;
    static const unsigned char sig1[] = {
        0xF6, 0x45, 0x57, 0x08, 0x0F, 0x84, 0x9C, 0x00, 0x00, 0x00
    };
    static const unsigned char sig2[] = {
        0xF6, 0x45, 0x57, 0x08, 0x74, 0x39
    };
    /* Get_Vert_Blank: push ebx,ecx,edx,esi,edi; mov eax, 0x005A2E58 */
    static const unsigned char sig_vb[] = {
        0x53, 0x51, 0x52, 0x56, 0x57, 0xB8, 0x58, 0x2E, 0x5A, 0x00
    };
    (void)inst;
    (void)prev;
    (void)cmd;
    (void)show;
    g_t0 = GetTickCount();
    g_log = fopen("Z:\\tmp\\ss1-cnc-capslie.log", "w");
    if (g_log)
        setvbuf(g_log, NULL, _IONBF, 0);
    flog("capslie start pid=%lu", (unsigned long)GetCurrentProcessId());

    t0wait = GetTickCount();
    while (GetTickCount() - t0wait < 20000) {
        pid = find_pid("C&C95.EXE");
        if (!pid)
            pid = find_pid("c&c95.exe");
        if (pid)
            break;
        Sleep(30);
    }
    if (!pid) {
        flog("C&C95.EXE not seen");
        goto done;
    }
    flog("found C&C pid=%lu", (unsigned long)pid);
    hp = OpenProcess(PROCESS_VM_OPERATION | PROCESS_VM_READ | PROCESS_VM_WRITE |
                     PROCESS_QUERY_INFORMATION, FALSE, pid);
    if (!hp) {
        flog("OpenProcess failed %lu", (unsigned long)GetLastError());
        goto done;
    }

    {
        DWORD tmod = GetTickCount();
        unsigned char mz[2];
        SIZE_T n = 0;
        base = 0;
        while (GetTickCount() - tmod < 8000) {
            base = module_base(pid, "C&C95.EXE");
            if (!base)
                base = module_base(pid, "c&c95.exe");
            if (!base)
                base = 0x400000;
            mz[0] = mz[1] = 0;
            if (ReadProcessMemory(hp, (void *)base, mz, 2, &n) && n == 2 &&
                mz[0] == 'M' && mz[1] == 'Z' &&
                read_ok(hp, base + 0xA9C5D, sig1, sizeof sig1))
                break;
            base = 0;
            Sleep(40);
        }
        flog("module base=0x%lx", (unsigned long)base);
        if (!base) {
            CloseHandle(hp);
            goto done;
        }
    }

    if (!read_ok(hp, base + 0xA9C5D, sig1, sizeof sig1)) {
        unsigned char got[10];
        SIZE_T n = 0;
        ReadProcessMemory(hp, (void *)(base + 0xA9C5D), got, 10, &n);
        flog("sig1 mismatch got %02x %02x %02x %02x %02x %02x",
             got[0], got[1], got[2], got[3], got[4], got[5]);
        CloseHandle(hp);
        goto done;
    }
    if (!read_ok(hp, base + 0xA9DAA, sig2, sizeof sig2))
        flog("sig2 mismatch (back-buffer site); continuing with primary only");

    cave = (DWORD_PTR)VirtualAllocEx(hp, NULL, 256, MEM_COMMIT | MEM_RESERVE,
                                     PAGE_EXECUTE_READWRITE);
    flog("cave=0x%lx", (unsigned long)cave);
    if (!cave) {
        CloseHandle(hp);
        goto done;
    }

    /* Primary GetCaps test: RVA 0xA9C5D, success 0xA9D03, fail 0xA9C67 */
    if (!plant(hp, base + 0xA9C5D, cave, sig1, sizeof sig1,
               base + 0xA9D03, base + 0xA9C67)) {
        CloseHandle(hp);
        goto done;
    }
    /* Back-buffer GetCaps: RVA 0xA9DAA, sysmem fallback 0xA9DE9, videomem path 0xA9DB0 */
    if (read_ok(hp, base + 0xA9DAA, sig2, sizeof sig2)) {
        plant(hp, base + 0xA9DAA, cave + 64, sig2, sizeof sig2,
              base + 0xA9DE9, base + 0xA9DB0);
        /* NOTE: original je is TAKEN when SYSTEMMEMORY is set (fallback).
         * After we clear SYSTEMMEMORY the je is NOT taken, execution continues
         * at 0xA9DB0 (treat as video memory). plant() uses je_target as the
         * taken branch; for site2 taken-on-sysmem is the fallback. After the
         * lie, test ZF=1 would TAKE je and wrongly go to sysmem fallback.
         *
         * After clearing SYSTEMMEMORY, ZF=1 still? test byte [ebp+57],08
         * with bit clear => ZF=1 => JE taken. That would send us to fallback
         * which is the SYSTEMMEMORY path — opposite of what we want for site2!
         *
         * Site1: JE to SUCCESS when bit clear. Correct.
         * Site2: JE to SYSMEM FALLBACK when bit set? Let's re-read bytes.
         *
         * Site2: F6 45 57 08 74 39
         * je 0x4a9de9 if ZF=1, i.e. if SYSTEMMEMORY bit is CLEAR.
         *
         * Wait. test byte, 08h: ZF=1 if bit CLEAR (not system memory).
         * Site1: 0F 84 -> JE success if NOT systemmemory. Correct.
         * Site2: 74 39 -> JE 4a9de9 if NOT systemmemory.
         *
         * 0x4a9de9 was "mov edx, 0x00541b5c; call copy" — the comment in
         * earlier disasm said je 0x4a9de9 on SYSTEMMEMORY. That's WRONG
         * relative to ZF. JE is taken when bit is CLEAR.
         *
         * Site2 je to 0x4a9de9 when NOT system memory?
         * 0x4a9dae je 0x4a9de9; fallthrough 0x4a9db0 starts with
         * mov eax, 0x00567c58 and SetPalette-like — "video mem path"
         * if we DON'T jump, we have SYSTEMMEMORY set.
         *
         * test bit 3 of high caps byte:
         * - bit SET (SYSTEMMEMORY) => ZF=0 => JNE, fall through to 0x4a9db0
         * - bit CLEAR (not SYSTEMMEMORY) => ZF=1 => JE 0x4a9de9
         *
         * That's INVERTED from site1!
         *
         * Site1: JE success if NOT sysmem (bit clear). Fallthrough = fail MessageBox if sysmem.
         * Site2: JE 0x4a9de9 if NOT sysmem. Fallthrough 0x4a9db0 if sysmem.
         *
         * That would mean site2 TREATS system memory as the path that calls
         * 0x4cc594 and keeps going as video? That doesn't match Westwood source.
         *
         * Recheck site2 address: 0x4a9daa test; 0x4a9dae je 0x4a9de9.
         * 0x4a9daa+4 = 0x4a9dae, 0x74 0x39, 0x4a9dae+2+0x39 = 0x4a9de9. Yes.
         *
         * 0x4a9db0: mov eax, 0x567c58; GetCaps failed sysmem? then Release surface
         * and recreate in system memory (0x4c9970). That's "if SYSTEMMEMORY, release
         * and make a sysmem buffer" — would be JNZ not JE.
         *
         * UNLESS 0x4a9db0 is the video path (bit was set? ZF=0 fallthrough).
         * If SYSTEMMEMORY is set, fall through to release-and-recreate? That matches
         * Cache_It: if SYSTEMMEMORY, Release and fail/recreate.
         *
         * Then JE when bit CLEAR would skip the release — keep the surface as
         * video memory. 0x4a9de9 copy GraphicBuffer.
         *
         * Site2 JE (bit clear / NOT sysmem) -> 0x4a9de9 keep/copy as video
         * Site2 fallthrough (bit set / sysmem) -> 0x4a9db0 release and recreate sysmem
         *
         * After our LIE (clear sysmem, set vidmem): bit clear, JE taken -> 0x4a9de9
         * which is the "it is video memory, keep it" path. CORRECT.
         *
         * plant(je_target=0xA9DE9, fallthrough=0xA9DB0) is correct for site2.
         */
    }

    /* Get_Vert_Blank RVA 0xDD550: majority-vote IN 0x3DA. One caller caches
     * the boolean. Immediate EAX=0 is the skip experiment (no port I/O). */
    if (read_ok(hp, base + 0xDD550, sig_vb, sizeof sig_vb)) {
        static const unsigned char skip_vb[] = {
            0x31, 0xC0, 0xC3, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90
        };
        if (write_all(hp, base + 0xDD550, skip_vb, sizeof skip_vb))
            flog("vblank skip planted RVA 0xDD550 xor eax,eax; ret");
        else
            flog("vblank skip write failed");
    } else {
        flog("vblank sig mismatch at 0x%lx", (unsigned long)(base + 0xDD550));
    }

    flog("caps lie + vblank skip armed; leaving C&C running");
    CloseHandle(hp);
    /* Stay alive briefly so logs flush; C&C does not depend on us. */
    Sleep(500);
done:
    if (g_log)
        fclose(g_log);
    return 0;
}
