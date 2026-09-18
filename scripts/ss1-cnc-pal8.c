/*
 * Inject ss1-cnc-pal8.dll into stock C&C95.EXE (disk unchanged).
 *
 * i686-w64-mingw32-gcc -O2 -Wall -s -mwindows -o ss1-cnc-pal8.exe \
 *     ss1-cnc-pal8.c -static-libgcc
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static FILE *g_log;

static void flog(const char *fmt, ...)
{
	va_list ap;
	if (!g_log)
		return;
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

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
	DWORD t0, pid = 0;
	HANDLE hp = NULL, thr = NULL;
	void *remote = NULL;
	char dll[MAX_PATH];
	SIZE_T n = 0;
	DWORD tid = 0;
	(void)inst;
	(void)prev;
	(void)cmd;
	(void)show;

	g_log = fopen("Z:\\tmp\\ss1-cnc-pal8-inject.log", "w");
	if (g_log)
		setvbuf(g_log, NULL, _IONBF, 0);

	GetModuleFileNameA(NULL, dll, MAX_PATH);
	{
		char *slash = strrchr(dll, '\\');
		if (slash)
			slash[1] = 0;
		else
			dll[0] = 0;
		lstrcatA(dll, "ss1-cnc-pal8.dll");
	}
	flog("dll=%s", dll);
	if (GetFileAttributesA(dll) == INVALID_FILE_ATTRIBUTES) {
		flog("dll missing");
		goto done;
	}

	t0 = GetTickCount();
	while (GetTickCount() - t0 < 25000) {
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
	flog("pid=%lu", (unsigned long)pid);

	hp = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION |
	                 PROCESS_VM_WRITE | PROCESS_VM_READ |
	                 PROCESS_QUERY_INFORMATION, FALSE, pid);
	if (!hp) {
		flog("OpenProcess %lu", (unsigned long)GetLastError());
		goto done;
	}

	n = lstrlenA(dll) + 1;
	remote = VirtualAllocEx(hp, NULL, n, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
	if (!remote || !WriteProcessMemory(hp, remote, dll, n, &n)) {
		flog("WriteProcessMemory failed %lu", (unsigned long)GetLastError());
		goto done;
	}

	thr = CreateRemoteThread(hp, NULL, 0,
	                         (LPTHREAD_START_ROUTINE)LoadLibraryA,
	                         remote, 0, &tid);
	if (!thr) {
		flog("CreateRemoteThread %lu", (unsigned long)GetLastError());
		goto done;
	}
	WaitForSingleObject(thr, 10000);
	flog("injected tid=%lu", (unsigned long)tid);

done:
	if (thr)
		CloseHandle(thr);
	if (remote && hp)
		VirtualFreeEx(hp, remote, 0, MEM_RELEASE);
	if (hp)
		CloseHandle(hp);
	if (g_log)
		fclose(g_log);
	return 0;
}
