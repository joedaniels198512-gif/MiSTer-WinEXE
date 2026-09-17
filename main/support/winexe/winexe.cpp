// WinEXE support for MiSTer_WinEXE (custom Main via core INI main=).
// T[n] actions are handled from user_io_status_set: menu.cpp already pulses
// 1 then 0 in the same handler, so polling cur_status later never sees them.
// Do not clear T bits here.
//
// .WEX selection is intercepted in user_io_file_tx so the file is never
// streamed into FPGA memory. Restart/Stop keep using T[5]/T[6].

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../../user_io.h"

char is_winexe();

#define WINEXE_LAUNCHER "/media/fat/Windows/bin/ss1-winexe-launch.sh"

static int winexe_spawn(const char *arg1, const char *arg2)
{
	pid_t pid = fork();
	if (pid < 0)
	{
		printf("WinEXE: fork failed\n");
		return -1;
	}
	if (pid == 0)
	{
		setsid();
		if (arg2 && arg2[0])
			execl("/bin/sh", "sh", WINEXE_LAUNCHER, arg1, arg2, (char *)0);
		else
			execl("/bin/sh", "sh", WINEXE_LAUNCHER, arg1, (char *)0);
		_exit(127);
	}
	return 0;
}

void winexe_init()
{
	if (!is_winexe()) return;

	printf("WinEXE: ARM profile core, idle until Load Application\n");
	winexe_spawn("idle", NULL);
}

void winexe_poll()
{
	// T pulses are observed in winexe_status_event(); .WEX in winexe_wex_selected().
}

void winexe_wex_selected(const char *path)
{
	if (!is_winexe() || !path || !path[0]) return;

	printf("WinEXE: Load Application %s\n", path);
	winexe_spawn("launch-wex", path);
}

void winexe_status_event(const char *opt, uint32_t value)
{
	if (!is_winexe() || !opt || !value) return;

	int start = 0, end = 0;
	if (!user_io_status_bits(opt, &start, &end, 0)) return;

	if (start == 5)
	{
		printf("WinEXE: Restart\n");
		winexe_spawn("restart", NULL);
	}
	else if (start == 6)
	{
		printf("WinEXE: Stop -> idle\n");
		winexe_spawn("idle", NULL);
	}
}
