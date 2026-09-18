/*
 * Civ II-only Linux CDROM ioctl shim.
 *
 * Wine MCICDA analog PLAYMSF is the working path under Box86 (CDDA
 * RAW_READ uses a nested pointer Wine/Box86 does not translate).
 *
 * CD playback is one worker thread:
 *   PCM 44.1 kHz S16 stereo → stateful 48 kHz S16 → mixer ring
 * paced on CLOCK_MONOTONIC. STATUS/SUBCHNL never restart the stream.
 *
 * A second persistent mixer thread is the only /dev/MrAudio writer:
 *   Wine ALSA (48 kHz S16 stereo via type file) + CD ring
 *   → saturate-add mix → 48 kHz S16 stereo → /dev/MrAudio
 * Wine open("/dev/MrAudio") is redirected to a pipe the mixer drains.
 *
 * Original BIN/CUE is not modified. Do not load this for other apps.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/cdrom.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define FRAMES_PER_SEC 75
#define FRAMES_PER_MIN 4500
#define T1_SECTORS     200674
#define T2_PREGAP      150
#define FIRST_AUDIO    2
#define LAST_TRACK     12
#define BYTES_PER_FR   2352
#define IN_RATE        44100
#define OUT_RATE       48000
#define OUT_CHUNK      4800 /* 100 ms at 48 kHz stereo (CD producer) */
#define MIX_PERIOD     960  /* 20 ms mixer period */
#define CD_RING_FRAMES 12000 /* 250 ms */
#define LOG_PATH       "/tmp/ss1-civ2-cdaudio.log"
#ifndef F_SETPIPE_SZ
#define F_SETPIPE_SZ 1031
#endif

typedef int (*ioctl_fn)(int, unsigned long, ...);
typedef int (*open_fn)(const char *, int, ...);
typedef int (*openat_fn)(int, const char *, int, ...);

static ioctl_fn real_ioctl;
static open_fn real_open;
static openat_fn real_openat;
static int enabled;
static char audio_dir[256];
static int t_sectors[LAST_TRACK + 2];
static int t_start[LAST_TRACK + 2];

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static pthread_t worker;
static int worker_started;
static int run_worker;
static int playing;
static int paused;
static int play_start_frame;
static int play_end_frame;
static int play_cur_frame;
static int req_seq;

static __thread int tls_mraudio;
static FILE *logf;
static int last_status_sec = -1;
static int logged_divert;

static pthread_mutex_t mix_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t start_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_t mix_thread;
static int mix_started;
static int mix_lockfd = -1;
static int run_mixer;
static int16_t cd_ring[CD_RING_FRAMES * 2];
static unsigned cd_head, cd_count;
static int wine_rd = -1, wine_wr = -1;
static unsigned long wine_bytes, wine_writes, mix_clips;

static void log_ts(const char *s)
{
	struct timespec ts;
	if (!logf) {
		logf = fopen(LOG_PATH, "a");
		if (logf)
			setvbuf(logf, NULL, _IOLBF, 0);
	}
	if (!logf)
		return;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	fprintf(logf, "t=%ld.%03ld %s\n",
		(long)ts.tv_sec, ts.tv_nsec / 1000000L, s);
	fflush(logf);
}

static int lba_to_frame(int lba)
{
	return lba + 150;
}

static void frame_to_msf(int frame, uint8_t *m, uint8_t *s, uint8_t *f)
{
	if (frame < 0)
		frame = 0;
	*m = (uint8_t)(frame / FRAMES_PER_MIN);
	*s = (uint8_t)((frame / FRAMES_PER_SEC) % 60);
	*f = (uint8_t)(frame % FRAMES_PER_SEC);
}

static int msf_to_frame(int m, int s, int f)
{
	return m * FRAMES_PER_MIN + s * FRAMES_PER_SEC + f;
}

static int track_for_frame(int frame)
{
	int t;

	for (t = LAST_TRACK; t >= 1; t--) {
		if (frame >= t_start[t])
			return t;
	}
	return 1;
}

static int interesting_path(const char *p)
{
	const char *b;

	if (!p || !p[0])
		return 0;
	if (strcasestr(p, ".avi") || strcasestr(p, "council") ||
	    strcasestr(p, "anarchy") || strcasestr(p, "/VIDEO") ||
	    strcasestr(p, "/video") || strcasestr(p, "\\video") ||
	    strcasestr(p, "mciwnd") || strcasestr(p, "msvidc"))
		return 1;
	b = strrchr(p, '/');
	return b && strcasestr(b, "civ2") && strcasestr(b, "video");
}

static void maybe_log_open(const char *tag, const char *path, int fd, int err)
{
	char line[400];

	if (!enabled || !interesting_path(path))
		return;
	if (fd >= 0)
		snprintf(line, sizeof line, "OPEN %s '%s' fd=%d", tag, path, fd);
	else
		snprintf(line, sizeof line, "OPEN %s '%s' FAIL errno=%d",
			 tag, path, err);
	log_ts(line);
}

static int16_t sat16(int32_t x)
{
	if (x > 32767)
		return 32767;
	if (x < -32768)
		return -32768;
	return (int16_t)x;
}

static void cd_push(const int16_t *frames, int nframes)
{
	int i;

	pthread_mutex_lock(&mix_mu);
	for (i = 0; i < nframes; i++) {
		unsigned p;
		if (cd_count == CD_RING_FRAMES) {
			cd_head = (cd_head + 1) % CD_RING_FRAMES;
			cd_count--;
		}
		p = (cd_head + cd_count) % CD_RING_FRAMES;
		cd_ring[p * 2] = frames[i * 2];
		cd_ring[p * 2 + 1] = frames[i * 2 + 1];
		cd_count++;
	}
	pthread_mutex_unlock(&mix_mu);
}

static void cd_pop(int16_t *dst, int nframes)
{
	int i;

	pthread_mutex_lock(&mix_mu);
	for (i = 0; i < nframes; i++) {
		if (cd_count == 0) {
			dst[i * 2] = 0;
			dst[i * 2 + 1] = 0;
		} else {
			dst[i * 2] = cd_ring[cd_head * 2];
			dst[i * 2 + 1] = cd_ring[cd_head * 2 + 1];
			cd_head = (cd_head + 1) % CD_RING_FRAMES;
			cd_count--;
		}
	}
	pthread_mutex_unlock(&mix_mu);
}

static void cd_flush(void)
{
	pthread_mutex_lock(&mix_mu);
	cd_head = 0;
	cd_count = 0;
	pthread_mutex_unlock(&mix_mu);
}

static int ensure_wine_pipe(void)
{
	int p[2];

	pthread_mutex_lock(&mix_mu);
	if (wine_rd >= 0 && wine_wr >= 0) {
		pthread_mutex_unlock(&mix_mu);
		return 0;
	}
	if (pipe(p) != 0) {
		pthread_mutex_unlock(&mix_mu);
		log_ts("wine pipe FAIL");
		return -1;
	}
	fcntl(p[0], F_SETFL, O_NONBLOCK);
	fcntl(p[1], F_SETFL, 0);
	fcntl(p[0], F_SETPIPE_SZ, 262144);
	fcntl(p[1], F_SETPIPE_SZ, 262144);
	wine_rd = p[0];
	wine_wr = p[1];
	pthread_mutex_unlock(&mix_mu);
	log_ts("divert Wine/ALSA /dev/MrAudio -> mixer pipe (48k S16 stereo)");
	logged_divert = 1;
	return 0;
}

static void *mixer_loop(void *arg)
{
	int mra;
	int16_t wine[MIX_PERIOD * 2];
	int16_t cd[MIX_PERIOD * 2];
	int16_t out[MIX_PERIOD * 2];
	int16_t hold[MIX_PERIOD * 8];
	int hold_n = 0;
	struct timespec deadline;
	int have_deadline = 0;
	unsigned last_log = 0;
	(void)arg;

	tls_mraudio = 1;
	mra = real_open("/dev/MrAudio", O_WRONLY);
	if (mra < 0) {
		log_ts("mixer MrAudio open FAIL");
		tls_mraudio = 0;
		return NULL;
	}
	log_ts("mixer start period=20ms one writer /dev/MrAudio");

	while (run_mixer) {
		ssize_t n;
		int need, got, i;
		unsigned now_sec;
		struct timespec ts;

		if (!have_deadline) {
			clock_gettime(CLOCK_MONOTONIC, &deadline);
			have_deadline = 1;
		}
		deadline.tv_nsec += (1000000000L / OUT_RATE) * MIX_PERIOD;
		while (deadline.tv_nsec >= 1000000000L) {
			deadline.tv_sec++;
			deadline.tv_nsec -= 1000000000L;
		}
		clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &deadline, NULL);

		/* Drain Wine pipe into hold, then take one period. */
		if (wine_rd >= 0) {
			for (;;) {
				size_t space = sizeof hold - (size_t)hold_n * 4;
				if (space < 4)
					break;
				n = read(wine_rd, ((char *)hold) + hold_n * 4, space);
				if (n <= 0)
					break;
				wine_bytes += (unsigned long)n;
				wine_writes++;
				hold_n += (int)(n / 4);
			}
		}
		need = MIX_PERIOD;
		got = hold_n < need ? hold_n : need;
		if (got > 0) {
			memcpy(wine, hold, (size_t)got * 4);
			if (hold_n > got)
				memmove(hold, hold + got * 2, (size_t)(hold_n - got) * 4);
			hold_n -= got;
		}
		if (got < need)
			memset(wine + got * 2, 0, (size_t)(need - got) * 4);

		cd_pop(cd, MIX_PERIOD);
		for (i = 0; i < MIX_PERIOD * 2; i++) {
			int32_t s = (int32_t)wine[i] + (int32_t)cd[i];
			if (s > 32767 || s < -32768)
				mix_clips++;
			out[i] = sat16(s);
		}
		if (write(mra, out, sizeof out) != (ssize_t)sizeof out)
			; /* keep going; FPGA underrun is worse than a short write */

		clock_gettime(CLOCK_MONOTONIC, &ts);
		now_sec = (unsigned)ts.tv_sec;
		if (now_sec != last_log) {
			char line[220];
			last_log = now_sec;
			snprintf(line, sizeof line,
				 "mix wine_bytes=%lu wine_wr=%lu cd_frames=%u clip=%lu",
				 wine_bytes, wine_writes, cd_count, mix_clips);
			log_ts(line);
		}
	}
	close(mra);
	return NULL;
}

static int self_is_civ2(void)
{
	char buf[64];
	int fd, n;

	fd = real_open("/proc/self/comm", O_RDONLY);
	if (fd < 0)
		return 0;
	n = (int)read(fd, buf, sizeof buf - 1);
	close(fd);
	if (n <= 0)
		return 0;
	buf[n] = 0;
	return strstr(buf, "civ2") != NULL;
}

static void ensure_mixer(void)
{
	pthread_mutex_lock(&start_mu);
	if (mix_started == 1) {
		pthread_mutex_unlock(&start_mu);
		return;
	}
	if (!self_is_civ2()) {
		pthread_mutex_unlock(&start_mu);
		return;
	}
	mix_lockfd = real_open("/tmp/ss1-civ2-mix.lock", O_CREAT | O_RDWR, 0666);
	if (mix_lockfd < 0 || flock(mix_lockfd, LOCK_EX | LOCK_NB) != 0) {
		if (mix_lockfd >= 0) {
			close(mix_lockfd);
			mix_lockfd = -1;
		}
		log_ts("mixer skipped (lock busy)");
		pthread_mutex_unlock(&start_mu);
		return;
	}
	run_mixer = 1;
	if (ensure_wine_pipe() != 0) {
		run_mixer = 0;
		pthread_mutex_unlock(&start_mu);
		return;
	}
	if (pthread_create(&mix_thread, NULL, mixer_loop, NULL) == 0) {
		mix_started = 1;
		pthread_detach(mix_thread);
	} else {
		run_mixer = 0;
		log_ts("mixer pthread_create FAIL");
	}
	pthread_mutex_unlock(&start_mu);
}

static int wine_mraudio_fd(void)
{
	ensure_mixer();
	if (wine_wr < 0)
		return real_open("/dev/null", O_WRONLY);
	return dup(wine_wr);
}

static void init_toc(void)
{
	int t, lba = 0;
	char path[300];
	struct stat st;

	t_start[1] = lba_to_frame(0);
	t_sectors[1] = T1_SECTORS;
	lba = T1_SECTORS + T2_PREGAP;
	for (t = 2; t <= LAST_TRACK; t++) {
		t_start[t] = lba_to_frame(lba);
		snprintf(path, sizeof path, "%s/track%02d.pcm", audio_dir, t);
		t_sectors[t] = 1;
		if (stat(path, &st) == 0 && st.st_size >= BYTES_PER_FR)
			t_sectors[t] = (int)(st.st_size / BYTES_PER_FR);
		lba += t_sectors[t];
	}
	t_start[LAST_TRACK + 1] = lba_to_frame(lba);
	t_sectors[LAST_TRACK + 1] = 0;
}

static int open_track_pcm(int track, int rel_frames)
{
	char path[300];
	int fd;

	if (track < FIRST_AUDIO || track > LAST_TRACK)
		return -1;
	snprintf(path, sizeof path, "%s/track%02d.pcm", audio_dir, track);
	fd = real_open(path, O_RDONLY);
	if (fd < 0)
		return -1;
	if (rel_frames > 0)
		lseek(fd, (off_t)rel_frames * BYTES_PER_FR, SEEK_SET);
	return fd;
}

static void pace_chunk(struct timespec *next)
{
	next->tv_nsec += (1000000000L / OUT_RATE) * OUT_CHUNK;
	while (next->tv_nsec >= 1000000000L) {
		next->tv_sec++;
		next->tv_nsec -= 1000000000L;
	}
	clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, next, NULL);
}

static void *play_thread(void *arg)
{
	int fd = -1, track = -1, seq = -1;
	int16_t in_l = 0, in_r = 0, prev_l = 0, prev_r = 0;
	int frac = 0; /* 0 .. OUT_RATE-1, input-hold accumulator */
	int16_t out[OUT_CHUNK * 2];
	int out_n = 0;
	struct timespec deadline;
	int have_deadline = 0;
	(void)arg;

	for (;;) {
		int local_play, local_pause, start_fr, end_fr, cur, local_seq;
		int t, rel;
		unsigned char sec[BYTES_PER_FR];
		ssize_t n;
		int i;

		pthread_mutex_lock(&mu);
		while (run_worker && (!playing || paused)) {
			if (fd >= 0) {
				close(fd);
				fd = -1;
				track = -1;
			}
			have_deadline = 0;
			out_n = 0;
			frac = 0;
			pthread_cond_wait(&cv, &mu);
		}
		if (!run_worker) {
			pthread_mutex_unlock(&mu);
			break;
		}
		local_play = playing;
		local_pause = paused;
		start_fr = play_start_frame;
		end_fr = play_end_frame;
		cur = play_cur_frame;
		local_seq = req_seq;
		pthread_mutex_unlock(&mu);

		if (!local_play || local_pause)
			continue;

		if (local_seq != seq) {
			seq = local_seq;
			if (fd >= 0) {
				close(fd);
				fd = -1;
			}
			track = -1;
			frac = 0;
			out_n = 0;
			prev_l = prev_r = in_l = in_r = 0;
			have_deadline = 0;
			cur = start_fr;
		}

		if (cur >= end_fr) {
			pthread_mutex_lock(&mu);
			if (req_seq == seq) {
				playing = 0;
				pthread_cond_broadcast(&cv);
			}
			pthread_mutex_unlock(&mu);
			continue;
		}

		t = track_for_frame(cur);
		if (t < FIRST_AUDIO)
			t = FIRST_AUDIO;
		if (t != track) {
			if (fd >= 0)
				close(fd);
			rel = cur - t_start[t];
			if (rel < 0)
				rel = 0;
			fd = open_track_pcm(t, rel);
			track = t;
			if (fd < 0) {
				char line[160];
				snprintf(line, sizeof line,
					 "worker missing track=%d", t);
				log_ts(line);
				pthread_mutex_lock(&mu);
				playing = 0;
				pthread_mutex_unlock(&mu);
				continue;
			}
		}

		n = read(fd, sec, BYTES_PER_FR);
		if (n < BYTES_PER_FR) {
			track = -1;
			if (fd >= 0) {
				close(fd);
				fd = -1;
			}
			cur++;
			pthread_mutex_lock(&mu);
			if (req_seq == seq)
				play_cur_frame = cur;
			pthread_mutex_unlock(&mu);
			continue;
		}

		/* One CD sector = 588 stereo S16 frames at 44.1 kHz.
		 * Emit 48 kHz with stateful ratio 48000/44100 (zero-order,
		 * continuous across sectors — never restart the converter). */
		for (i = 0; i < 588; i++) {
			prev_l = in_l;
			prev_r = in_r;
			in_l = (int16_t)(sec[i * 4] | (sec[i * 4 + 1] << 8));
			in_r = (int16_t)(sec[i * 4 + 2] | (sec[i * 4 + 3] << 8));
			frac += OUT_RATE;
			while (frac >= IN_RATE) {
				int32_t num, ol, oor;

				frac -= IN_RATE;
				num = IN_RATE - frac;
				if (num < 0)
					num = 0;
				if (num > IN_RATE)
					num = IN_RATE;
				ol = prev_l + (int32_t)(in_l - prev_l) * num / IN_RATE;
				oor = prev_r + (int32_t)(in_r - prev_r) * num / IN_RATE;
				out[out_n * 2] = (int16_t)ol;
				out[out_n * 2 + 1] = (int16_t)oor;
				out_n++;
				if (out_n == OUT_CHUNK) {
					if (!have_deadline) {
						clock_gettime(CLOCK_MONOTONIC,
							      &deadline);
						have_deadline = 1;
					}
					cd_push(out, OUT_CHUNK);
					pace_chunk(&deadline);
					out_n = 0;
				}
			}
		}

		cur++;
		pthread_mutex_lock(&mu);
		if (req_seq == seq)
			play_cur_frame = cur;
		pthread_mutex_unlock(&mu);
	}

	if (fd >= 0)
		close(fd);
	if (out_n > 0)
		cd_push(out, out_n);
	return NULL;
}

static void ensure_worker(void)
{
	if (worker_started)
		return;
	run_worker = 1;
	if (pthread_create(&worker, NULL, play_thread, NULL) == 0) {
		worker_started = 1;
		pthread_detach(worker);
	} else {
		run_worker = 0;
		log_ts("worker pthread_create FAIL");
	}
}

static void request_play(int start_frame, int end_frame)
{
	char line[200];
	uint8_t m0, s0, f0, m1, s1, f1;
	int track, same;

	if (end_frame <= start_frame)
		end_frame = start_frame + 1;
	track = track_for_frame(start_frame);
	if (track < FIRST_AUDIO)
		track = FIRST_AUDIO;

	pthread_mutex_lock(&mu);
	same = playing && !paused &&
		play_start_frame == start_frame &&
		play_end_frame == end_frame;
	if (!same) {
		play_start_frame = start_frame;
		play_end_frame = end_frame;
		play_cur_frame = start_frame;
		paused = 0;
		playing = 1;
		req_seq++;
		ensure_worker();
		ensure_mixer();
		pthread_cond_broadcast(&cv);
	}
	pthread_mutex_unlock(&mu);

	frame_to_msf(start_frame, &m0, &s0, &f0);
	frame_to_msf(end_frame, &m1, &s1, &f1);
	snprintf(line, sizeof line,
		 "PLAY %u:%u:%u-%u:%u:%u track=%d from=%d to=%d%s",
		 m0, s0, f0, m1, s1, f1, track, start_frame, end_frame,
		 same ? " (keep)" : "");
	log_ts(line);
}

static void request_stop(void)
{
	pthread_mutex_lock(&mu);
	if (playing || paused)
		log_ts("STOP");
	playing = 0;
	paused = 0;
	cd_flush();
	pthread_cond_broadcast(&cv);
	pthread_mutex_unlock(&mu);
}

static void request_pause(void)
{
	pthread_mutex_lock(&mu);
	if (playing && !paused) {
		paused = 1;
		log_ts("PAUSE");
		pthread_cond_broadcast(&cv);
	}
	pthread_mutex_unlock(&mu);
}

static void request_resume(void)
{
	pthread_mutex_lock(&mu);
	if (playing && paused) {
		paused = 0;
		log_ts("RESUME");
		pthread_cond_broadcast(&cv);
	}
	pthread_mutex_unlock(&mu);
}

static int handle_ioctl(int fd, unsigned long req, void *arg)
{
	char line[200];
	(void)fd;

	switch (req) {
	case CDROMREADTOCHDR: {
		struct cdrom_tochdr *h = arg;
		if (!h) {
			errno = EFAULT;
			return -1;
		}
		h->cdth_trk0 = 1;
		h->cdth_trk1 = LAST_TRACK;
		log_ts("OPEN/TOC tracks 1-12");
		return 0;
	}
	case CDROMREADTOCENTRY: {
		struct cdrom_tocentry *e = arg;
		int tr, frame;

		if (!e) {
			errno = EFAULT;
			return -1;
		}
		tr = e->cdte_track;
		if (tr == CDROM_LEADOUT)
			tr = LAST_TRACK + 1;
		if (tr < 1 || tr > LAST_TRACK + 1) {
			errno = EINVAL;
			return -1;
		}
		frame = t_start[tr];
		e->cdte_adr = 1;
		e->cdte_ctrl = (tr == 1) ? 4 : 0;
		if (e->cdte_format == CDROM_LBA)
			e->cdte_addr.lba = frame - 150;
		else {
			e->cdte_format = CDROM_MSF;
			frame_to_msf(frame, &e->cdte_addr.msf.minute,
				     &e->cdte_addr.msf.second,
				     &e->cdte_addr.msf.frame);
		}
		e->cdte_datamode = (tr == 1) ? 1 : 0;
		return 0;
	}
	case CDROMSTART:
		return 0;
	case CDROMSTOP:
		request_stop();
		return 0;
	case CDROMPAUSE:
		request_pause();
		return 0;
	case CDROMRESUME:
		request_resume();
		return 0;
	case CDROMPLAYMSF: {
		struct cdrom_msf *m = arg;
		int a, b;

		if (!m) {
			errno = EFAULT;
			return -1;
		}
		a = msf_to_frame(m->cdmsf_min0, m->cdmsf_sec0, m->cdmsf_frame0);
		b = msf_to_frame(m->cdmsf_min1, m->cdmsf_sec1, m->cdmsf_frame1);
		request_play(a, b);
		return 0;
	}
	case CDROMPLAYTRKIND: {
		struct cdrom_ti *ti = arg;
		int a, b;

		if (!ti) {
			errno = EFAULT;
			return -1;
		}
		a = t_start[ti->cdti_trk0 < 1 ? 1 : ti->cdti_trk0];
		b = (ti->cdti_trk1 >= LAST_TRACK)
			? t_start[LAST_TRACK + 1] - 1
			: t_start[ti->cdti_trk1 + 1] - 1;
		snprintf(line, sizeof line, "PLAYTRKIND %u-%u",
			 ti->cdti_trk0, ti->cdti_trk1);
		log_ts(line);
		request_play(a, b);
		return 0;
	}
	case CDROMSUBCHNL: {
		struct cdrom_subchnl *sc = arg;
		int fr, tr, play, pause_now;
		uint8_t m, s, f;
		struct timespec ts;

		if (!sc) {
			errno = EFAULT;
			return -1;
		}
		pthread_mutex_lock(&mu);
		play = playing;
		pause_now = paused;
		fr = play ? play_cur_frame : t_start[FIRST_AUDIO];
		pthread_mutex_unlock(&mu);
		tr = track_for_frame(fr);
		if (play)
			sc->cdsc_audiostatus = pause_now ? CDROM_AUDIO_PAUSED
							 : CDROM_AUDIO_PLAY;
		else
			sc->cdsc_audiostatus = CDROM_AUDIO_NO_STATUS;
		sc->cdsc_adr = 1;
		sc->cdsc_ctrl = (tr == 1) ? 4 : 0;
		sc->cdsc_trk = (uint8_t)tr;
		sc->cdsc_ind = 1;
		frame_to_msf(fr, &m, &s, &f);
		if (sc->cdsc_format == CDROM_LBA) {
			sc->cdsc_absaddr.lba = fr - 150;
			sc->cdsc_reladdr.lba = fr - t_start[tr];
		} else {
			sc->cdsc_format = CDROM_MSF;
			sc->cdsc_absaddr.msf.minute = m;
			sc->cdsc_absaddr.msf.second = s;
			sc->cdsc_absaddr.msf.frame = f;
			frame_to_msf(fr - t_start[tr], &m, &s, &f);
			sc->cdsc_reladdr.msf.minute = m;
			sc->cdsc_reladdr.msf.second = s;
			sc->cdsc_reladdr.msf.frame = f;
		}
		clock_gettime(CLOCK_MONOTONIC, &ts);
		if ((int)ts.tv_sec != last_status_sec) {
			last_status_sec = (int)ts.tv_sec;
			snprintf(line, sizeof line,
				 "STATUS %s pos=%u:%u:%u track=%d",
				 play ? (pause_now ? "PAUSE" : "PLAY") : "STOP",
				 m, s, f, tr);
			log_ts(line);
		}
		return 0;
	}
	case CDROMSEEK: {
		struct cdrom_msf *m = arg;
		int a;

		if (!m) {
			errno = EFAULT;
			return -1;
		}
		a = msf_to_frame(m->cdmsf_min0, m->cdmsf_sec0, m->cdmsf_frame0);
		snprintf(line, sizeof line, "SEEK %u:%u:%u frame=%d",
			 m->cdmsf_min0, m->cdmsf_sec0, m->cdmsf_frame0, a);
		log_ts(line);
		pthread_mutex_lock(&mu);
		if (playing) {
			play_cur_frame = a;
			play_start_frame = a;
			req_seq++;
			paused = 0;
			pthread_cond_broadcast(&cv);
		}
		pthread_mutex_unlock(&mu);
		return 0;
	}
	case CDROM_DRIVE_STATUS:
		return CDS_DISC_OK;
	case CDROM_DISC_STATUS:
		return CDS_MIXED;
	case CDROM_GET_CAPABILITY:
		return CDC_PLAY_AUDIO | CDC_DRIVE_STATUS | CDC_LOCK |
		       CDC_MULTI_SESSION;
	case CDROM_MEDIA_CHANGED:
		return 0;
	case CDROM_LOCKDOOR:
	case CDROMRESET:
	case CDROMEJECT:
	case CDROMCLOSETRAY:
	case CDROMVOLCTRL:
	case CDROMVOLREAD:
		return 0;
	case CDROMREADRAW:
	case CDROMREADAUDIO:
		/* Nested-pointer RAW_READ is unsafe under Box86. Analog PLAYMSF. */
		errno = EINVAL;
		return -1;
	default:
		break;
	}
	errno = ENOTTY;
	return -1;
}

static int is_cdrom_req(unsigned long req)
{
	unsigned long nr = req & 0xffff;
	return nr >= 0x5301 && nr <= 0x5395;
}

static void init_once(void)
{
	const char *dir;

	if (real_ioctl)
		return;
	real_ioctl = (ioctl_fn)dlsym(RTLD_NEXT, "ioctl");
	real_open = (open_fn)dlsym(RTLD_NEXT, "open");
	real_openat = (openat_fn)dlsym(RTLD_NEXT, "openat");
	dir = getenv("SS1_CIV2_CDAUDIO_DIR");
	if (!dir || !dir[0])
		dir = "/media/fat/Windows/apps/civ2/cdaudio";
	snprintf(audio_dir, sizeof audio_dir, "%s", dir);
	enabled = (getenv("SS1_CIV2_CDAUDIO") &&
		   getenv("SS1_CIV2_CDAUDIO")[0] != '0');
	if (!enabled && getenv("SS1_CIV2_CDAUDIO_DIR"))
		enabled = 1;
	init_toc();
}

__attribute__((constructor))
static void ctor(void)
{
	init_once();
	if (enabled)
		ensure_mixer();
}

int ioctl(int fd, unsigned long request, ...)
{
	va_list ap;
	void *arg;

	init_once();
	va_start(ap, request);
	arg = va_arg(ap, void *);
	va_end(ap);
	if (enabled && is_cdrom_req(request))
		return handle_ioctl(fd, request, arg);
	return real_ioctl(fd, request, arg);
}

int open(const char *path, int flags, ...)
{
	va_list ap;
	mode_t mode = 0;
	int fd;

	init_once();
	if (enabled && !tls_mraudio && path && strcmp(path, "/dev/MrAudio") == 0) {
		int fd = wine_mraudio_fd();
		if (fd >= 0)
			return fd;
	}
	if (flags & O_CREAT) {
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
	}
	if (flags & O_CREAT)
		fd = real_open(path, flags, mode);
	else
		fd = real_open(path, flags);
	maybe_log_open("open", path, fd, errno);
	return fd;
}

int openat(int dirfd, const char *path, int flags, ...)
{
	va_list ap;
	mode_t mode = 0;
	int fd;

	init_once();
	if (enabled && !tls_mraudio && path && strcmp(path, "/dev/MrAudio") == 0) {
		int wfd = wine_mraudio_fd();
		if (wfd >= 0)
			return wfd;
	}
	if (flags & O_CREAT) {
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
	}
	if (flags & O_CREAT)
		fd = real_openat(dirfd, path, flags, mode);
	else
		fd = real_openat(dirfd, path, flags);
	maybe_log_open("openat", path, fd, errno);
	return fd;
}

int open64(const char *path, int flags, ...)
{
	va_list ap;
	mode_t mode = 0;

	if (flags & O_CREAT) {
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
		return open(path, flags, mode);
	}
	return open(path, flags);
}

int openat64(int dirfd, const char *path, int flags, ...)
{
	va_list ap;
	mode_t mode = 0;

	if (flags & O_CREAT) {
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
		return openat(dirfd, path, flags, mode);
	}
	return openat(dirfd, path, flags);
}
