/*
 * Map WinEXE PAL8 + mailbox DDR into the Box86/Wine process at identity VAs.
 * ARM LD_PRELOAD .so. Guest x86 then writes 0x30200000 / 0x30400000 directly.
 *
 *   arm-linux-gnueabihf-gcc -O2 -Wall -fPIC -shared -o ss1-pal8-map.so ss1-pal8-map.c
 */
#define _GNU_SOURCE
#include "ss1-pal8.h"

#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define PAL8_MAP_LEN  0x00200000UL  /* 0x30200000 .. 0x303FFFFF */

static void *g_pal8;
static void *g_mbox;
static int g_fd = -1;
static volatile int g_run;

static void slog(const char *msg)
{
	FILE *f = fopen(SS1_PAL8_MAP_LOG, "a");
	if (!f)
		return;
	fprintf(f, "%s\n", msg);
	fclose(f);
}

static void write_stats_file(void)
{
	volatile uint32_t *st;
	volatile uint32_t *mb;
	FILE *f;
	uint64_t sum, bytes;
	uint32_t copies, i, n, max_ns, p95;
	uint32_t ring[SS1_STAT_RING_N];

	if (!g_pal8 || !g_mbox)
		return;
	st = (volatile uint32_t *)((char *)g_pal8 + (SS1_PAL8_STATS_PHYS - SS1_PAL8_PHYS));
	mb = (volatile uint32_t *)g_mbox;
	copies = st[SS1_STAT_COPIES / 4];
	sum = (uint64_t)st[SS1_STAT_COPY_NS_SUM / 4] |
	      ((uint64_t)st[SS1_STAT_COPY_NS_SUM / 4 + 1] << 32);
	bytes = (uint64_t)st[SS1_STAT_BYTES / 4] |
	        ((uint64_t)st[SS1_STAT_BYTES / 4 + 1] << 32);
	max_ns = st[SS1_STAT_COPY_NS_MAX / 4];
	for (i = 0; i < SS1_STAT_RING_N; i++)
		ring[i] = st[(SS1_STAT_RING / 4) + i];

	/* insertion sort a copy for p95 */
	{
		uint32_t j, t, used = 0;
		uint32_t tmp[SS1_STAT_RING_N];
		for (i = 0; i < SS1_STAT_RING_N; i++) {
			if (ring[i])
				tmp[used++] = ring[i];
		}
		for (i = 1; i < used; i++) {
			t = tmp[i];
			j = i;
			while (j > 0 && tmp[j - 1] > t) {
				tmp[j] = tmp[j - 1];
				j--;
			}
			tmp[j] = t;
		}
		p95 = used ? tmp[(used * 95) / 100] : 0;
		n = used;
	}

	f = fopen(SS1_PAL8_STATS_PATH, "w");
	if (!f)
		return;
	fprintf(f, "pal8_en=%u pal_gen=%u presents=%u copies=%u avg_copy_ns=%llu p95_copy_ns=%u max_copy_ns=%u bytes=%llu mBps=%.2f ring=%u\n",
		mb[SS1_MBOX_OFF_FLAGS / 4] & SS1_PAL8_FLAG_EN,
		mb[SS1_MBOX_OFF_PAL_GEN / 4],
		mb[SS1_MBOX_OFF_PRESENTS / 4],
		copies,
		copies ? (unsigned long long)(sum / copies) : 0ull,
		p95, max_ns,
		(unsigned long long)bytes,
		/* last-second rate is not known here; report lifetime avg */
		(sum > 0) ? ((double)bytes / (double)sum * 1e9 / 1e6) : 0.0,
		n);
	fclose(f);
}

static void *stats_thread(void *arg)
{
	(void)arg;
	while (g_run) {
		volatile uint32_t *mb = g_mbox;
		if (mb && mb[SS1_MBOX_OFF_MAGIC / 4] == SS1_PAL8_MAGIC &&
		    (mb[SS1_MBOX_OFF_FLAGS / 4] & SS1_PAL8_FLAG_EN)) {
			int fd = open(SS1_PAL8_ACTIVE_PATH, O_CREAT | O_WRONLY, 0644);
			if (fd >= 0)
				close(fd);
			write_stats_file();
		} else {
			unlink(SS1_PAL8_ACTIVE_PATH);
		}
		sleep(1);
	}
	return NULL;
}

static void pal8_off(void)
{
	g_run = 0;
	/* Shared physical mailbox: do not clear pal8_en here. Helpers that
	 * inherit LD_PRELOAD would otherwise clobber C&C's enable bit.
	 * ss1-cnc-pal8.sh stop clears flags on profile teardown. */
	unlink(SS1_PAL8_ACTIVE_PATH);
}

__attribute__((constructor))
static void pal8_map_init(void)
{
	const char *en;
	void *want;
	pthread_t th;

	en = getenv("SS1_PAL8");
	if (!en || en[0] == '0')
		return;

	g_fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (g_fd < 0) {
		slog("open /dev/mem failed");
		return;
	}

	want = (void *)(uintptr_t)SS1_PAL8_PHYS;
	g_pal8 = mmap(want, PAL8_MAP_LEN, PROT_READ | PROT_WRITE,
		      MAP_SHARED | MAP_FIXED, g_fd, (off_t)SS1_PAL8_PHYS);
	if (g_pal8 == MAP_FAILED || g_pal8 != want) {
		slog("mmap PAL8 0x30200000 failed");
		g_pal8 = NULL;
		close(g_fd);
		g_fd = -1;
		return;
	}

	want = (void *)(uintptr_t)SS1_MBOX_PHYS;
	g_mbox = mmap(want, SS1_MBOX_SIZE, PROT_READ | PROT_WRITE,
		      MAP_SHARED | MAP_FIXED, g_fd, (off_t)SS1_MBOX_PHYS);
	if (g_mbox == MAP_FAILED || g_mbox != want) {
		slog("mmap mailbox 0x30400000 failed");
		munmap(g_pal8, PAL8_MAP_LEN);
		g_pal8 = NULL;
		g_mbox = NULL;
		close(g_fd);
		g_fd = -1;
		return;
	}

	{
		volatile uint32_t *mb = g_mbox;
		if (mb[SS1_MBOX_OFF_MAGIC / 4] != SS1_PAL8_MAGIC) {
			mb[SS1_MBOX_OFF_MAGIC / 4] = SS1_PAL8_MAGIC;
			mb[SS1_MBOX_OFF_FLAGS / 4] = 0; /* BGRX until hook succeeds */
			mb[SS1_MBOX_OFF_PAL_GEN / 4] = 0;
			mb[SS1_MBOX_OFF_PRESENTS / 4] = 0;
		}
	}
	memset((char *)g_pal8 + (SS1_PAL8_STATS_PHYS - SS1_PAL8_PHYS), 0,
	       SS1_PAL8_STATS_SIZE);

	g_run = 1;
	if (pthread_create(&th, NULL, stats_thread, NULL) == 0)
		pthread_detach(th);
	slog("mapped PAL8 0x30200000 + mailbox 0x30400000 (flags=0)");
	atexit(pal8_off);
}

__attribute__((destructor))
static void pal8_map_fini(void)
{
	pal8_off();
	if (g_pal8)
		munmap(g_pal8, PAL8_MAP_LEN);
	if (g_mbox)
		munmap(g_mbox, SS1_MBOX_SIZE);
	if (g_fd >= 0)
		close(g_fd);
}
