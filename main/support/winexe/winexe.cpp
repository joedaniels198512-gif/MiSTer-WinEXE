// WinEXE support for MiSTer_WinEXE (custom Main via core INI main=).
// T[n] actions are handled from user_io_status_set: menu.cpp already pulses
// 1 then 0 in the same handler, so polling cur_status later never sees them.
// Do not clear T bits here.
//
// .WEX selection is intercepted in user_io_file_tx so the file is never
// streamed into FPGA memory. Restart/Stop keep using T[5]/T[6].
//
// Spawn is double-forked + setsid so the launcher is not a child of Main
// and does not inherit Main's HOME=/ DISPLAY-unset environment or FDs.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "../../user_io.h"

char is_winexe();

#define WINEXE_LAUNCHER "/media/fat/Windows/bin/ss1-winexe-launch.sh"
#define WINEXE_SPAWN_LOG "/media/fat/Windows/logs/wex-spawn.log"

static void winexe_child_setup()
{
	int nfd, logfd, fd;

	setsid();
	chdir("/root");

	setenv("HOME", "/root", 1);
	setenv("USER", "root", 1);
	setenv("LOGNAME", "root", 1);
	setenv("DISPLAY", ":0", 1);
	setenv("PATH", "/media/fat/Windows/bin:/usr/bin:/bin:/usr/sbin:/sbin", 1);
	unsetenv("WAYLAND_DISPLAY");

	nfd = open("/dev/null", O_RDWR);
	if (nfd >= 0)
	{
		dup2(nfd, STDIN_FILENO);
		if (nfd > 2) close(nfd);
	}

	logfd = open(WINEXE_SPAWN_LOG, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (logfd >= 0)
	{
		dup2(logfd, STDOUT_FILENO);
		dup2(logfd, STDERR_FILENO);
		if (logfd > 2) close(logfd);
	}

	for (fd = 3; fd < 256; fd++)
		close(fd);
}

static int winexe_spawn(const char *arg1, const char *arg2)
{
	pid_t pid;

	pid = fork();
	if (pid < 0)
	{
		printf("WinEXE: fork failed\n");
		return -1;
	}
	if (pid > 0)
	{
		/* Reap the intermediate so Main does not collect a zombie.
		   The grandchild is already reparented to init. */
		waitpid(pid, NULL, 0);
		return 0;
	}

	winexe_child_setup();

	pid = fork();
	if (pid < 0)
		_exit(127);
	if (pid > 0)
		_exit(0);

	if (arg2 && arg2[0])
		execl("/bin/sh", "sh", WINEXE_LAUNCHER, arg1, arg2, (char *)0);
	else
		execl("/bin/sh", "sh", WINEXE_LAUNCHER, arg1, (char *)0);
	_exit(127);
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
