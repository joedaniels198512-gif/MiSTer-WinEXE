/*
 * Win32 CD presentation probe (same Wine prefix/session as C&C).
 * Does not patch C&C95.EXE. Optional --set-cdrom uses Wine mountmgr,
 * the same path winecfg uses to mark a drive as CD-ROM.
 *
 * i686-w64-mingw32-gcc -O2 -Wall -s -mwindows -o ss1-cnc-cdprobe.exe \
 *     ss1-cnc-cdprobe.c -static-libgcc
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

#define DRIVE_UNKNOWN     0
#define DRIVE_NO_ROOT_DIR 1
#define DRIVE_REMOVABLE   2
#define DRIVE_FIXED       3
#define DRIVE_REMOTE      4
#define DRIVE_CDROM       5
#define DRIVE_RAMDISK     6

#define MOUNTMGRCONTROLTYPE ((ULONG)'m')
#define IOCTL_MOUNTMGR_DEFINE_UNIX_DRIVE \
    CTL_CODE(MOUNTMGRCONTROLTYPE, 32, METHOD_BUFFERED, FILE_READ_ACCESS | FILE_WRITE_ACCESS)
#define IOCTL_MOUNTMGR_QUERY_UNIX_DRIVE \
    CTL_CODE(MOUNTMGRCONTROLTYPE, 33, METHOD_BUFFERED, FILE_READ_ACCESS)

#pragma pack(push, 8)
struct mountmgr_unix_drive {
    ULONG size;
    ULONG type;
    ULONG fs_type;
    DWORD serial;
    ULONGLONG unix_dev;
    WCHAR letter;
    USHORT mount_point_offset;
    USHORT device_offset;
    USHORT label_offset;
};
#pragma pack(pop)

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

static const char *dtype_name(UINT t)
{
    switch (t) {
    case 0: return "DRIVE_UNKNOWN";
    case 1: return "DRIVE_NO_ROOT_DIR";
    case 2: return "DRIVE_REMOVABLE";
    case 3: return "DRIVE_FIXED";
    case 4: return "DRIVE_REMOTE";
    case 5: return "DRIVE_CDROM";
    case 6: return "DRIVE_RAMDISK";
    default: return "?";
    }
}

static HANDLE open_mountmgr(DWORD access)
{
    return CreateFileA("\\\\.\\MountPointManager", access,
                       FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                       OPEN_EXISTING, 0, NULL);
}

static void dump_mountmgr(char letter)
{
    HANDLE mgr;
    struct mountmgr_unix_drive in;
    unsigned char buf[1024];
    DWORD br = 0;
    struct mountmgr_unix_drive *out = (struct mountmgr_unix_drive *)buf;

    mgr = open_mountmgr(GENERIC_READ);
    if (mgr == INVALID_HANDLE_VALUE) {
        flog("mountmgr open failed gle=%lu", (unsigned long)GetLastError());
        return;
    }
    memset(&in, 0, sizeof in);
    in.letter = (WCHAR)letter;
    memset(buf, 0, sizeof buf);
    if (!DeviceIoControl(mgr, IOCTL_MOUNTMGR_QUERY_UNIX_DRIVE,
                         &in, sizeof in, buf, sizeof buf, &br, NULL)) {
        flog("mountmgr QUERY %c: failed gle=%lu", letter, (unsigned long)GetLastError());
        CloseHandle(mgr);
        return;
    }
    flog("mountmgr %c: type=%lu fs_type=%lu serial=0x%08lx unix_dev=0x%llx mp_off=%u dev_off=%u lab_off=%u",
         letter, (unsigned long)out->type, (unsigned long)out->fs_type,
         (unsigned long)out->serial, (unsigned long long)out->unix_dev,
         (unsigned)out->mount_point_offset, (unsigned)out->device_offset,
         (unsigned)out->label_offset);
    if (out->mount_point_offset)
        flog("  unix mount=%s", (char *)buf + out->mount_point_offset);
    if (out->device_offset)
        flog("  unix device=%s", (char *)buf + out->device_offset);
    if (out->label_offset)
        flog("  label_w=%ls", (WCHAR *)(buf + out->label_offset));
    CloseHandle(mgr);
}

static int set_drive_cdrom(char letter)
{
    HANDLE mgr;
    struct mountmgr_unix_drive in;
    unsigned char qbuf[1024];
    unsigned char *ioctl;
    struct mountmgr_unix_drive *q, *d;
    char *mp = NULL, *dev = NULL;
    size_t mp_n = 0, dev_n = 0, len;
    DWORD br = 0;
    int ok = 0;

    mgr = open_mountmgr(GENERIC_READ | GENERIC_WRITE);
    if (mgr == INVALID_HANDLE_VALUE) {
        flog("set-cdrom: mountmgr open gle=%lu", (unsigned long)GetLastError());
        return 0;
    }
    memset(&in, 0, sizeof in);
    in.letter = (WCHAR)letter;
    memset(qbuf, 0, sizeof qbuf);
    if (!DeviceIoControl(mgr, IOCTL_MOUNTMGR_QUERY_UNIX_DRIVE,
                         &in, sizeof in, qbuf, sizeof qbuf, &br, NULL)) {
        flog("set-cdrom: QUERY failed gle=%lu", (unsigned long)GetLastError());
        CloseHandle(mgr);
        return 0;
    }
    q = (struct mountmgr_unix_drive *)qbuf;
    if (q->mount_point_offset)
        mp = (char *)qbuf + q->mount_point_offset;
    if (q->device_offset)
        dev = (char *)qbuf + q->device_offset;
    mp_n = mp ? strlen(mp) + 1 : 0;
    dev_n = dev ? strlen(dev) + 1 : 0;
    len = sizeof(struct mountmgr_unix_drive) + mp_n + dev_n;
    ioctl = (unsigned char *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, len);
    if (!ioctl) {
        CloseHandle(mgr);
        return 0;
    }
    d = (struct mountmgr_unix_drive *)ioctl;
    d->size = (ULONG)len;
    d->type = DRIVE_CDROM;
    d->letter = (WCHAR)(letter >= 'A' && letter <= 'Z' ? letter - 'A' + 'a' : letter);
    if (mp_n) {
        memcpy(ioctl + sizeof(*d), mp, mp_n);
        d->mount_point_offset = (USHORT)sizeof(*d);
        if (dev_n) {
            memcpy(ioctl + sizeof(*d) + mp_n, dev, dev_n);
            d->device_offset = (USHORT)(sizeof(*d) + mp_n);
        }
    }
    if (!DeviceIoControl(mgr, IOCTL_MOUNTMGR_DEFINE_UNIX_DRIVE,
                         ioctl, (DWORD)len, NULL, 0, &br, NULL)) {
        flog("set-cdrom: DEFINE failed gle=%lu", (unsigned long)GetLastError());
    } else {
        flog("set-cdrom: DEFINE %c: type=DRIVE_CDROM mp=%s dev=%s",
             letter, mp ? mp : "", dev ? dev : "");
        ok = 1;
    }
    HeapFree(GetProcessHeap(), 0, ioctl);
    CloseHandle(mgr);
    return ok;
}

static void probe_drive(char letter)
{
    char root[8], mix[32];
    UINT dtype;
    char vol[MAX_PATH], fs[MAX_PATH];
    DWORD serial = 0, maxc = 0, flags = 0;
    BOOL vok;
    DWORD gle;
    HANDLE hf;
    DWORD attr;

    wsprintfA(root, "%c:\\", letter);
    wsprintfA(mix, "%c:\\movies.mix", letter);

    SetLastError(0);
    dtype = GetDriveTypeA(root);
    gle = GetLastError();
    flog("%c: GetDriveType=%u (%s) gle=%lu", letter, dtype, dtype_name(dtype), (unsigned long)gle);

    if (dtype == DRIVE_NO_ROOT_DIR)
        return;

    vol[0] = fs[0] = 0;
    SetLastError(0);
    vok = GetVolumeInformationA(root, vol, sizeof vol, &serial, &maxc, &flags, fs, sizeof fs);
    gle = GetLastError();
    flog("%c: GetVolumeInformation ok=%d gle=%lu label='%s' fs='%s' serial=0x%08lx flags=0x%lx",
         letter, (int)vok, (unsigned long)gle, vol, fs,
         (unsigned long)serial, (unsigned long)flags);

    SetLastError(0);
    hf = CreateFileA(mix, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                     NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    gle = GetLastError();
    flog("%c: CreateFile('%s') %s gle=%lu",
         letter, mix, hf == INVALID_HANDLE_VALUE ? "FAIL" : "OK", (unsigned long)gle);
    if (hf != INVALID_HANDLE_VALUE)
        CloseHandle(hf);

    if (letter == 'D' || letter == 'd') {
        SetLastError(0);
        attr = GetFileAttributesA("D:\\movies.mix");
        gle = GetLastError();
        flog("D: GetFileAttributes('D:\\\\movies.mix')=0x%lx gle=%lu",
             (unsigned long)attr, (unsigned long)gle);
        dump_mountmgr('D');
        dump_mountmgr('d');
    }
}

static void list_root(const char *root)
{
    char pat[16];
    WIN32_FIND_DATAA fd;
    HANDLE h;
    int n = 0;

    wsprintfA(pat, "%s*", root);
    h = FindFirstFileA(pat, &fd);
    if (h == INVALID_HANDLE_VALUE) {
        flog("FindFirstFile '%s' gle=%lu", pat, (unsigned long)GetLastError());
        return;
    }
    do {
        flog("  %s %s", (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? "DIR " : "FILE",
             fd.cFileName);
        n++;
        if (n >= 40) {
            flog("  ... truncated");
            break;
        }
    } while (FindNextFileA(h, &fd));
    FindClose(h);
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    char letter;
    int set_cdrom = 0;
    (void)inst;
    (void)prev;
    (void)show;
    g_t0 = GetTickCount();
    g_log = fopen("Z:\\tmp\\ss1-cnc-cdprobe.log", "w");
    if (!g_log)
        g_log = fopen("C:\\ss1-cnc-cdprobe.log", "w");
    if (g_log)
        setvbuf(g_log, NULL, _IONBF, 0);
    flog("cdprobe start pid=%lu cmd='%s'", (unsigned long)GetCurrentProcessId(),
         cmd ? cmd : "");

    if (cmd && strstr(cmd, "--set-cdrom"))
        set_cdrom = 1;

    if (set_cdrom) {
        HKEY hk = 0;
        if (RegCreateKeyExA(HKEY_LOCAL_MACHINE, "Software\\Wine\\Drives", 0, NULL,
                            0, KEY_SET_VALUE, NULL, &hk, NULL) == ERROR_SUCCESS) {
            const char *v = "cdrom";
            RegSetValueExA(hk, "d:", 0, REG_SZ, (const BYTE *)v, 6);
            RegSetValueExA(hk, "D:", 0, REG_SZ, (const BYTE *)v, 6);
            RegCloseKey(hk);
            flog("registry HKLM\\Software\\Wine\\Drives d:=cdrom");
        } else {
            flog("registry Drives create gle=%lu", (unsigned long)GetLastError());
        }
        set_drive_cdrom('d');
        set_drive_cdrom('D');
    }

    for (letter = 'C'; letter <= 'Z'; letter++)
        probe_drive(letter);

    flog("=== D: root ===");
    list_root("D:\\");
    flog("cdprobe done");
    if (g_log)
        fclose(g_log);
    return 0;
}
