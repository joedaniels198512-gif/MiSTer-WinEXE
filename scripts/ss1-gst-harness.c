/* Tiny i386 Linux GStreamer harness for Box86 (no Wine, no X11, no audio).
 *
 * Dynamically loads libgstreamer-1.0.so.0 via dlopen so Box86 can wrap the
 * native ARMHF library. Linked only against libc/libdl (Bullseye glibc 2.31).
 *
 * Stages via SS1_GST_STAGE / argv[1]:
 *   find      gst_init + gst_element_factory_find("wavparse")   (Test A)
 *   plugin    find + plugin/feature accessors + factory_create/make
 *   pipeline  plugin + filesrc ! wavparse ! fakesink to EOS
 */
#include <dlfcn.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef void GstElement;
typedef void GstElementFactory;
typedef void GstPlugin;
typedef void GstPluginFeature;
typedef void GstBus;
typedef void GstMessage;
typedef unsigned int guint;
typedef char gchar;
typedef int gboolean;
typedef uint64_t GstClockTime;

#define GST_STATE_NULL 1
#define GST_STATE_READY 2
#define GST_STATE_PAUSED 3
#define GST_STATE_PLAYING 4
#define GST_STATE_CHANGE_FAILURE 0
#define GST_STATE_CHANGE_SUCCESS 1
#define GST_STATE_CHANGE_ASYNC 2
#define GST_STATE_CHANGE_NO_PREROLL 3
#define GST_FORMAT_TIME 3
#define GST_SECOND ((GstClockTime)1000000000ULL)
#define GST_CLOCK_TIME_NONE ((GstClockTime)-1)
#define GST_MESSAGE_EOS (1 << 1)
#define GST_MESSAGE_ERROR (1 << 2)
#define GST_MESSAGE_WARNING (1 << 3)
#define GST_MESSAGE_TAG (1 << 5)
#define GST_MESSAGE_STATE_CHANGED (1 << 7)
#define GST_MESSAGE_DURATION_CHANGED (1 << 19)
#define GST_MESSAGE_LATENCY (1 << 20)
#define GST_MESSAGE_ASYNC_DONE (1 << 22)
#define GST_MESSAGE_STREAM_START (1 << 29)
#define GST_BUS_WATCH \
    (GST_MESSAGE_EOS | GST_MESSAGE_ERROR | GST_MESSAGE_WARNING | GST_MESSAGE_TAG | \
     GST_MESSAGE_STATE_CHANGED | GST_MESSAGE_DURATION_CHANGED | GST_MESSAGE_LATENCY | \
     GST_MESSAGE_ASYNC_DONE | GST_MESSAGE_STREAM_START)

static void *libgst;

static void (*p_gst_init)(int *, char ***);
static void (*p_gst_version)(guint *, guint *, guint *, guint *);
static const gchar *(*p_gst_version_string)(void);
static GstElementFactory *(*p_gst_element_factory_find)(const gchar *);
static const gchar *(*p_gst_plugin_feature_get_plugin_name)(GstPluginFeature *);
static GstPlugin *(*p_gst_plugin_feature_get_plugin)(GstPluginFeature *);
static const gchar *(*p_gst_plugin_get_filename)(GstPlugin *);
static const gchar *(*p_gst_plugin_get_name)(GstPlugin *);
static gboolean (*p_gst_plugin_is_loaded)(GstPlugin *);
static GstPluginFeature *(*p_gst_plugin_feature_load)(GstPluginFeature *);
static GstElement *(*p_gst_element_factory_create)(GstElementFactory *, const gchar *);
static GstElement *(*p_gst_element_factory_make)(const gchar *, const gchar *);
static gboolean (*p_gst_bin_add)(GstElement *, GstElement *);
static gboolean (*p_gst_element_link)(GstElement *, GstElement *);
static int (*p_gst_element_set_state)(GstElement *, int);
static int (*p_gst_element_get_state)(GstElement *, int *, int *, GstClockTime);
static int (*p_gst_element_query_position)(GstElement *, int, int64_t *);
static int (*p_gst_element_query_duration)(GstElement *, int, int64_t *);
static GstBus *(*p_gst_element_get_bus)(GstElement *);
static GstMessage *(*p_gst_bus_timed_pop_filtered)(GstBus *, GstClockTime, int);
static GstMessage *(*p_gst_bus_pop)(GstBus *);
static GstMessage *(*p_gst_bus_peek)(GstBus *);
static gboolean (*p_gst_bus_have_pending)(GstBus *);
static void (*p_gst_util_set_object_arg)(void *, const gchar *, const gchar *);
static void (*p_gst_message_unref)(void *);
static void (*p_gst_message_parse_error)(GstMessage *, void **, gchar **);
static void (*p_gst_message_parse_state_changed)(GstMessage *, int *, int *, int *);
static const gchar *(*p_gst_message_type_get_name)(int);
static gchar *(*p_gst_object_get_name)(void *);
static void *(*p_gst_object_unref)(void *);
static void (*p_g_free)(void *);
static void (*p_gst_deinit)(void);
static void *libglib;

static void flush_print(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stdout, fmt, ap);
    va_end(ap);
    fflush(stdout);
    fflush(stderr);
}

static void print_mem(const char *tag)
{
    FILE *f = fopen("/proc/self/status", "r");
    unsigned long vmrss = 0, vmsize = 0;
    char line[256];
    if (f) {
        while (fgets(line, sizeof(line), f)) {
            if (sscanf(line, "VmRSS: %lu", &vmrss) == 1)
                continue;
            if (sscanf(line, "VmSize: %lu", &vmsize) == 1)
                continue;
        }
        fclose(f);
    }
    flush_print("MEM %s self_VmRSS_kB=%lu self_VmSize_kB=%lu\n", tag, vmrss, vmsize);
}

static void *try_dlsym(const char *name)
{
    void *s = dlsym(libgst, name);
    if (!s)
        flush_print("FAIL dlsym %s (%s)\n", name, dlerror());
    else
        flush_print("OK dlsym %s %p\n", name, s);
    return s;
}

static void *must_dlsym(const char *name)
{
    return try_dlsym(name);
}

static int stage_rank(const char *stage)
{
    if (!stage || !strcmp(stage, "find"))
        return 1;
    if (!strcmp(stage, "plugin"))
        return 2;
    if (!strcmp(stage, "pipeline") || !strcmp(stage, "all"))
        return 3;
    flush_print("FAIL unknown stage %s\n", stage);
    return -1;
}

static int run_plugin_accessors(GstElementFactory *factory)
{
    GstPlugin *plugin = NULL;
    GstPluginFeature *loaded = NULL;
    GstElement *created = NULL;
    GstElement *made = NULL;
    const gchar *plugin_name = NULL;
    const gchar *filename = NULL;
    const gchar *gst_name = NULL;

    flush_print("BEFORE gst_plugin_feature_get_plugin_name factory=%p\n", (void *)factory);
    plugin_name = p_gst_plugin_feature_get_plugin_name
                      ? p_gst_plugin_feature_get_plugin_name((GstPluginFeature *)factory)
                      : NULL;
    flush_print("AFTER gst_plugin_feature_get_plugin_name name=%s\n",
                plugin_name ? plugin_name : "(null)");

    flush_print("BEFORE gst_plugin_feature_get_plugin factory=%p\n", (void *)factory);
    plugin = p_gst_plugin_feature_get_plugin
                 ? p_gst_plugin_feature_get_plugin((GstPluginFeature *)factory)
                 : NULL;
    flush_print("AFTER gst_plugin_feature_get_plugin plugin=%p\n", (void *)plugin);

    if (plugin && p_gst_plugin_get_filename) {
        flush_print("BEFORE gst_plugin_get_filename plugin=%p\n", (void *)plugin);
        filename = p_gst_plugin_get_filename(plugin);
        flush_print("AFTER gst_plugin_get_filename filename=%s\n",
                    filename ? filename : "(null)");
    }
    if (plugin && p_gst_plugin_get_name) {
        flush_print("BEFORE gst_plugin_get_name plugin=%p\n", (void *)plugin);
        gst_name = p_gst_plugin_get_name(plugin);
        flush_print("AFTER gst_plugin_get_name name=%s\n", gst_name ? gst_name : "(null)");
    }
    if (plugin && p_gst_plugin_is_loaded) {
        flush_print("BEFORE gst_plugin_is_loaded plugin=%p\n", (void *)plugin);
        flush_print("AFTER gst_plugin_is_loaded loaded=%d\n",
                    (int)p_gst_plugin_is_loaded(plugin));
    }

    flush_print("BEFORE gst_plugin_feature_load factory=%p\n", (void *)factory);
    loaded = p_gst_plugin_feature_load
                 ? p_gst_plugin_feature_load((GstPluginFeature *)factory)
                 : NULL;
    flush_print("AFTER gst_plugin_feature_load loaded=%p\n", (void *)loaded);
    if (loaded && loaded != (GstPluginFeature *)factory && p_gst_object_unref)
        p_gst_object_unref(loaded);

    flush_print("BEFORE gst_element_factory_create factory=%p name=NULL\n", (void *)factory);
    created = p_gst_element_factory_create ? p_gst_element_factory_create(factory, NULL) : NULL;
    flush_print("AFTER gst_element_factory_create el=%p\n", (void *)created);
    if (created && p_gst_object_unref)
        p_gst_object_unref(created);

    flush_print("BEFORE gst_element_factory_make wavparse name=NULL\n");
    made = p_gst_element_factory_make ? p_gst_element_factory_make("wavparse", NULL) : NULL;
    flush_print("AFTER gst_element_factory_make el=%p\n", (void *)made);
    if (made && p_gst_object_unref)
        p_gst_object_unref(made);

    if (plugin && p_gst_object_unref)
        p_gst_object_unref(plugin);

    if (!created || !made) {
        flush_print("FAIL element creation created=%p made=%p\n", (void *)created, (void *)made);
        return 1;
    }
    flush_print("OK plugin accessors and element create/make\n");
    return 0;
}

static const char *state_name(int s)
{
    switch (s) {
    case 0: return "VOID_PENDING";
    case GST_STATE_NULL: return "NULL";
    case GST_STATE_READY: return "READY";
    case GST_STATE_PAUSED: return "PAUSED";
    case GST_STATE_PLAYING: return "PLAYING";
    default: return "?";
    }
}

static const char *change_name(int r)
{
    switch (r) {
    case GST_STATE_CHANGE_FAILURE: return "FAILURE";
    case GST_STATE_CHANGE_SUCCESS: return "SUCCESS";
    case GST_STATE_CHANGE_ASYNC: return "ASYNC";
    case GST_STATE_CHANGE_NO_PREROLL: return "NO_PREROLL";
    default: return "?";
    }
}

/* i386 GstMessage: GstMiniObject (36) then GstMessageType at offset 36. */
static int message_type(GstMessage *msg)
{
    return msg ? *(int *)((char *)msg + 36) : 0;
}

static void *message_src(GstMessage *msg)
{
    /* type(4) + pad-to-8 + timestamp(8) => src at 48 */
    return msg ? *(void **)((char *)msg + 48) : NULL;
}

static void print_query(GstElement *pipeline, const char *tag)
{
    int64_t pos = -1, dur = -1;
    int got_pos = 0, got_dur = 0;
    if (p_gst_element_query_position)
        got_pos = p_gst_element_query_position(pipeline, GST_FORMAT_TIME, &pos);
    if (p_gst_element_query_duration)
        got_dur = p_gst_element_query_duration(pipeline, GST_FORMAT_TIME, &dur);
    flush_print("QUERY %s position_ok=%d position_ns=%lld duration_ok=%d duration_ns=%lld\n",
                tag, got_pos, (long long)pos, got_dur, (long long)dur);
}

static void print_get_state(GstElement *pipeline, const char *tag, GstClockTime timeout)
{
    int cur = -1, pending = -1, ret = -1;
    if (!p_gst_element_get_state) {
        flush_print("FAIL gst_element_get_state missing (%s)\n", tag);
        return;
    }
    flush_print("BEFORE gst_element_get_state %s timeout_ns=%llu\n",
                tag, (unsigned long long)timeout);
    ret = p_gst_element_get_state(pipeline, &cur, &pending, timeout);
    flush_print("AFTER gst_element_get_state %s ret=%d (%s) current=%d (%s) pending=%d (%s)\n",
                tag, ret, change_name(ret), cur, state_name(cur), pending, state_name(pending));
}

static void describe_message(GstMessage *msg)
{
    int type = message_type(msg);
    const char *tname = p_gst_message_type_get_name ? p_gst_message_type_get_name(type) : "?";
    void *src = message_src(msg);
    char *srcname = NULL;
    if (src && p_gst_object_get_name)
        srcname = p_gst_object_get_name(src);
    flush_print("BUS msg=%p type=0x%x (%s) src=%p name=%s\n",
                (void *)msg, type, tname ? tname : "?", src,
                srcname ? srcname : "(null)");
    if (type == GST_MESSAGE_STATE_CHANGED && p_gst_message_parse_state_changed) {
        int olds = -1, news = -1, pending = -1;
        p_gst_message_parse_state_changed(msg, &olds, &news, &pending);
        flush_print("BUS STATE_CHANGED %s: %s -> %s pending %s\n",
                    srcname ? srcname : "?", state_name(olds), state_name(news),
                    state_name(pending));
    }
    if ((type == GST_MESSAGE_ERROR || type == GST_MESSAGE_WARNING) &&
        p_gst_message_parse_error) {
        void *err = NULL;
        char *dbg = NULL;
        p_gst_message_parse_error(msg, &err, &dbg);
        flush_print("BUS %s debug=%s gerror=%p\n",
                    type == GST_MESSAGE_ERROR ? "ERROR" : "WARNING",
                    dbg ? dbg : "(null)", err);
        if (dbg && p_g_free)
            p_g_free(dbg);
    }
    if (srcname && p_g_free)
        p_g_free(srcname);
}

static int is_named_type(GstMessage *msg, const char *want)
{
    int type = message_type(msg);
    const char *tname = p_gst_message_type_get_name ? p_gst_message_type_get_name(type) : NULL;
    return tname && want && strcmp(tname, want) == 0;
}

static int run_pipeline(const char *wav)
{
    GstElement *pipeline, *src, *parse, *sink;
    GstBus *bus = NULL;
    GstMessage *msg;
    int set_ret;
    int rc = 1;
    int saw_eos = 0, saw_error = 0, nmsg = 0, polls;
    const int max_polls = 24;

    flush_print("BEFORE pipeline factory_make filesrc/wavparse/fakesink wav=%s\n", wav);
    pipeline = p_gst_element_factory_make("pipeline", "ss1-pipe");
    src = p_gst_element_factory_make("filesrc", "src");
    parse = p_gst_element_factory_make("wavparse", "parse");
    sink = p_gst_element_factory_make("fakesink", "sink");
    flush_print("AFTER pipeline elements pipeline=%p src=%p parse=%p sink=%p\n",
                (void *)pipeline, (void *)src, (void *)parse, (void *)sink);
    if (!pipeline || !src || !parse || !sink)
        return 1;

    flush_print("BEFORE gst_util_set_object_arg location=%s\n", wav);
    if (p_gst_util_set_object_arg)
        p_gst_util_set_object_arg(src, "location", wav);
    flush_print("AFTER gst_util_set_object_arg\n");

    flush_print("BEFORE gst_bin_add x3\n");
    if (!p_gst_bin_add(pipeline, src) || !p_gst_bin_add(pipeline, parse) ||
        !p_gst_bin_add(pipeline, sink)) {
        flush_print("FAIL gst_bin_add\n");
        goto out;
    }
    flush_print("AFTER gst_bin_add\n");

    flush_print("BEFORE gst_element_link filesrc->wavparse->fakesink\n");
    if (!p_gst_element_link(src, parse) || !p_gst_element_link(parse, sink)) {
        flush_print("FAIL gst_element_link\n");
        goto out;
    }
    flush_print("AFTER gst_element_link\n");

    /* Hold the pipeline bus before PLAYING so queued STATE_CHANGED/EOS are not missed. */
    bus = p_gst_element_get_bus(pipeline);
    flush_print("BUS watch mask=0x%x bus=%p\n", GST_BUS_WATCH, (void *)bus);

    flush_print("BEFORE gst_element_set_state PLAYING\n");
    set_ret = p_gst_element_set_state(pipeline, GST_STATE_PLAYING);
    flush_print("AFTER gst_element_set_state PLAYING ret=%d (%s)\n",
                set_ret, change_name(set_ret));
    if (set_ret == GST_STATE_CHANGE_FAILURE) {
        flush_print("FAIL gst_element_set_state PLAYING\n");
        goto out;
    }

    print_get_state(pipeline, "after_set_playing", 2 * GST_SECOND);
    print_query(pipeline, "after_set_playing");
    flush_print("BUS have_pending=%d after_get_state\n",
                p_gst_bus_have_pending && bus ? p_gst_bus_have_pending(bus) : -1);

    /*
     * Native GST_BUS traces show timed_pop_filtered actually dequeues EOS, but the
     * Box86 pFpUi trampoline returns NULL to x86. Drain with gst_bus_pop (pFp)
     * which already works for factory_find/get_bus pointer returns.
     */
    for (polls = 0; polls < max_polls && !saw_eos && !saw_error; polls++) {
        int pending = p_gst_bus_have_pending && bus ? p_gst_bus_have_pending(bus) : -1;
        GstMessage *peeked = (p_gst_bus_peek && bus) ? p_gst_bus_peek(bus) : NULL;
        flush_print("BUS poll=%d have_pending=%d peek=%p\n", polls, pending, (void *)peeked);
        if (peeked && p_gst_message_unref)
            p_gst_message_unref(peeked);

        msg = NULL;
        if (pending && p_gst_bus_pop)
            msg = p_gst_bus_pop(bus);
        if (!msg && p_gst_bus_timed_pop_filtered) {
            flush_print("BEFORE gst_bus_timed_pop_filtered poll=%d timeout=250ms\n", polls);
            msg = p_gst_bus_timed_pop_filtered(bus, GST_SECOND / 4, GST_BUS_WATCH);
            flush_print("AFTER gst_bus_timed_pop_filtered poll=%d msg=%p\n",
                        polls, (void *)msg);
        }
        if (!msg) {
            usleep(250000);
            print_get_state(pipeline, "idle_poll", 0);
            print_query(pipeline, "idle_poll");
            continue;
        }
        nmsg++;
        describe_message(msg);
        /* Native type names: the i386 GstMessage.type offset is not 1:1 with
         * GST_MESSAGE_* flags under Box86, so match the wrapped get_name. */
        if (is_named_type(msg, "eos"))
            saw_eos = 1;
        if (is_named_type(msg, "error"))
            saw_error = 1;
        if (p_gst_message_unref)
            p_gst_message_unref(msg);
        print_query(pipeline, "after_bus_msg");
    }

    print_get_state(pipeline, "after_bus_loop", 0);
    print_query(pipeline, "after_bus_loop");
    flush_print("PIPELINE summary nmsg=%d saw_eos=%d saw_error=%d polls=%d\n",
                nmsg, saw_eos, saw_error, polls);
    if (saw_eos && !saw_error)
        rc = 0;
    else
        flush_print("FAIL pipeline did not reach EOS (preroll/dataflow stall)\n");

    if (bus && p_gst_object_unref)
        p_gst_object_unref(bus);
    bus = NULL;

    flush_print("BEFORE gst_element_set_state NULL\n");
    p_gst_element_set_state(pipeline, GST_STATE_NULL);
    flush_print("AFTER gst_element_set_state NULL\n");

out:
    if (pipeline && p_gst_object_unref)
        p_gst_object_unref(pipeline);
    return rc;
}

int main(int argc, char **argv)
{
    guint major = 0, minor = 0, micro = 0, nano = 0;
    GstElementFactory *factory = NULL;
    const char *stage = getenv("SS1_GST_STAGE");
    const char *wav = getenv("SS1_GST_WAV");
    int want;
    int rc = 0;

    if (argc > 1 && argv[1][0])
        stage = argv[1];
    if (!stage)
        stage = "find";
    if (!wav)
        wav = "/tmp/tone.wav";
    want = stage_rank(stage);
    if (want < 0)
        return 2;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    flush_print("HARNESS start pid=%d argc=%d stage=%s wav=%s\n",
                (int)getpid(), argc, stage, wav);
    print_mem("before_dlopen");

    flush_print("BEFORE dlopen libgstreamer-1.0.so.0\n");
    libgst = dlopen("libgstreamer-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!libgst) {
        flush_print("FAIL dlopen libgstreamer-1.0.so.0 (%s)\n", dlerror());
        return 3;
    }
    flush_print("AFTER dlopen libgstreamer-1.0.so.0 ok\n");

    p_gst_init = must_dlsym("gst_init");
    p_gst_version = try_dlsym("gst_version");
    p_gst_version_string = try_dlsym("gst_version_string");
    p_gst_element_factory_find = must_dlsym("gst_element_factory_find");
    p_gst_plugin_feature_get_plugin_name = try_dlsym("gst_plugin_feature_get_plugin_name");
    p_gst_plugin_feature_get_plugin = try_dlsym("gst_plugin_feature_get_plugin");
    p_gst_plugin_get_filename = try_dlsym("gst_plugin_get_filename");
    p_gst_plugin_get_name = try_dlsym("gst_plugin_get_name");
    p_gst_plugin_is_loaded = try_dlsym("gst_plugin_is_loaded");
    p_gst_plugin_feature_load = try_dlsym("gst_plugin_feature_load");
    p_gst_element_factory_create = try_dlsym("gst_element_factory_create");
    p_gst_element_factory_make = try_dlsym("gst_element_factory_make");
    p_gst_bin_add = try_dlsym("gst_bin_add");
    p_gst_element_link = try_dlsym("gst_element_link");
    p_gst_element_set_state = try_dlsym("gst_element_set_state");
    p_gst_element_get_state = try_dlsym("gst_element_get_state");
    p_gst_element_query_position = try_dlsym("gst_element_query_position");
    p_gst_element_query_duration = try_dlsym("gst_element_query_duration");
    p_gst_element_get_bus = try_dlsym("gst_element_get_bus");
    p_gst_bus_timed_pop_filtered = try_dlsym("gst_bus_timed_pop_filtered");
    p_gst_bus_pop = try_dlsym("gst_bus_pop");
    p_gst_bus_peek = try_dlsym("gst_bus_peek");
    p_gst_bus_have_pending = try_dlsym("gst_bus_have_pending");
    p_gst_util_set_object_arg = try_dlsym("gst_util_set_object_arg");
    p_gst_message_unref = try_dlsym("gst_message_unref");
    p_gst_message_parse_error = try_dlsym("gst_message_parse_error");
    p_gst_message_parse_state_changed = try_dlsym("gst_message_parse_state_changed");
    p_gst_message_type_get_name = try_dlsym("gst_message_type_get_name");
    p_gst_object_get_name = try_dlsym("gst_object_get_name");
    p_gst_object_unref = try_dlsym("gst_object_unref");
    p_gst_deinit = try_dlsym("gst_deinit");

    libglib = dlopen("libglib-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (libglib)
        p_g_free = dlsym(libglib, "g_free");
    if (p_g_free)
        flush_print("OK dlsym g_free %p\n", (void *)p_g_free);
    else
        flush_print("FAIL dlsym g_free\n");
    if (!p_gst_init || !p_gst_element_factory_find)
        return 4;

    print_mem("before_gst_init");
    flush_print("BEFORE gst_init\n");
    p_gst_init(&argc, &argv);
    if (p_gst_version)
        p_gst_version(&major, &minor, &micro, &nano);
    flush_print("AFTER gst_init version %u.%u.%u.%u (%s)\n",
                major, minor, micro, nano,
                p_gst_version_string ? p_gst_version_string() : "?");
    print_mem("after_gst_init");

    flush_print("BEFORE gst_element_factory_find wavparse\n");
    factory = p_gst_element_factory_find("wavparse");
    flush_print("AFTER gst_element_factory_find factory=%p\n", (void *)factory);
    print_mem("after_factory_find");
    if (!factory) {
        flush_print("FAIL factory_find wavparse (NULL)\n");
        rc = 1;
        goto done;
    }
    flush_print("OK factory_find wavparse factory=%p\n", (void *)factory);

    if (want >= 2) {
        if (run_plugin_accessors(factory) != 0)
            rc = 5;
        print_mem("after_plugin");
    }

    if (want >= 3 && rc == 0) {
        if (run_pipeline(wav) != 0)
            rc = 6;
        print_mem("after_pipeline");
    }

    if (factory && p_gst_object_unref)
        p_gst_object_unref(factory);

done:
    if (p_gst_deinit) {
        flush_print("BEFORE gst_deinit\n");
        p_gst_deinit();
        flush_print("AFTER gst_deinit\n");
    }
    print_mem("after_gst_deinit");
    flush_print("HARNESS done rc=%d stage=%s\n", rc, stage);
    return rc;
}
