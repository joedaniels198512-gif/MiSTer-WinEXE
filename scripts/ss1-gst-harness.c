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
#define GST_STATE_PLAYING 4
#define GST_CLOCK_TIME_NONE ((GstClockTime)-1)
#define GST_MESSAGE_EOS (1 << 1)
#define GST_MESSAGE_ERROR (1 << 2)

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
static GstBus *(*p_gst_element_get_bus)(GstElement *);
static GstMessage *(*p_gst_bus_timed_pop_filtered)(GstBus *, GstClockTime, int);
static void (*p_gst_util_set_object_arg)(void *, const gchar *, const gchar *);
static void (*p_gst_message_unref)(void *);
static void *(*p_gst_object_unref)(void *);
static void (*p_gst_deinit)(void);

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

static int run_pipeline(const char *wav)
{
    GstElement *pipeline, *src, *parse, *sink;
    GstBus *bus;
    GstMessage *msg;
    int rc = 1;

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

    flush_print("BEFORE gst_element_set_state PLAYING\n");
    if (p_gst_element_set_state(pipeline, GST_STATE_PLAYING) == 0) {
        flush_print("FAIL gst_element_set_state PLAYING\n");
        goto out;
    }
    flush_print("AFTER gst_element_set_state PLAYING\n");

    bus = p_gst_element_get_bus(pipeline);
    flush_print("BEFORE gst_bus_timed_pop_filtered EOS|ERROR bus=%p\n", (void *)bus);
    msg = p_gst_bus_timed_pop_filtered(bus, GST_CLOCK_TIME_NONE,
                                       GST_MESSAGE_EOS | GST_MESSAGE_ERROR);
    flush_print("AFTER gst_bus_timed_pop_filtered msg=%p\n", (void *)msg);
    if (msg) {
        /* GstMessage type is at a known offset; print pointer only. */
        flush_print("OK pipeline got bus message %p\n", (void *)msg);
        if (p_gst_message_unref)
            p_gst_message_unref(msg);
        rc = 0;
    }
    if (bus && p_gst_object_unref)
        p_gst_object_unref(bus);

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
    p_gst_element_get_bus = try_dlsym("gst_element_get_bus");
    p_gst_bus_timed_pop_filtered = try_dlsym("gst_bus_timed_pop_filtered");
    p_gst_util_set_object_arg = try_dlsym("gst_util_set_object_arg");
    p_gst_message_unref = try_dlsym("gst_message_unref");
    p_gst_object_unref = try_dlsym("gst_object_unref");
    p_gst_deinit = try_dlsym("gst_deinit");
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
