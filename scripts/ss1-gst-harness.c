/* Tiny i386 Linux GStreamer harness for Box86 (no Wine, no X11, no audio).
 *
 * Dynamically loads libgstreamer-1.0.so.0 via dlopen so Box86 can wrap the
 * native ARMHF library. Linked only against libc/libdl (Bullseye glibc 2.31).
 *
 *   box86 ss1-gst-harness
 * with the private ARMHF GStreamer LD_LIBRARY_PATH / GST_* env.
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
typedef void GObject;
typedef unsigned int guint;
typedef char gchar;

static void *libgst;

static void (*p_gst_init)(int *, char ***);
static void (*p_gst_version)(guint *, guint *, guint *, guint *);
static const gchar *(*p_gst_version_string)(void);
static GstElementFactory *(*p_gst_element_factory_find)(const gchar *);
static const gchar *(*p_gst_plugin_feature_get_plugin_name)(GstPluginFeature *);
static GstPlugin *(*p_gst_plugin_feature_get_plugin)(GstPluginFeature *);
static const gchar *(*p_gst_plugin_get_filename)(GstPlugin *);
static GstElement *(*p_gst_element_factory_make)(const gchar *, const gchar *);
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

static void *must_dlsym(const char *name)
{
    void *s = dlsym(libgst, name);
    if (!s)
        flush_print("FAIL dlsym %s (%s)\n", name, dlerror());
    return s;
}

static int try_element(const char *name)
{
    GstElementFactory *factory;
    GstPlugin *plugin;
    GstElement *el;
    const gchar *filename;
    const gchar *plugin_name;

    flush_print("STEP factory_find %s\n", name);
    factory = p_gst_element_factory_find(name);
    if (!factory) {
        flush_print("FAIL factory_find %s (NULL)\n", name);
        return 1;
    }

    plugin_name = p_gst_plugin_feature_get_plugin_name((GstPluginFeature *)factory);
    plugin = p_gst_plugin_feature_get_plugin((GstPluginFeature *)factory);
    filename = plugin ? p_gst_plugin_get_filename(plugin) : NULL;
    flush_print("OK factory_find %s plugin=%s filename=%s\n",
                name,
                plugin_name ? plugin_name : "(null)",
                filename ? filename : "(null)");
    if (plugin)
        p_gst_object_unref(plugin);

    flush_print("STEP factory_make %s\n", name);
    el = p_gst_element_factory_make(name, NULL);
    if (!el) {
        flush_print("FAIL factory_make %s\n", name);
        p_gst_object_unref(factory);
        return 1;
    }
    flush_print("OK factory_make %s ptr=%p\n", name, (void *)el);
    p_gst_object_unref(el);
    p_gst_object_unref(factory);
    flush_print("OK unref %s\n", name);
    return 0;
}

int main(int argc, char **argv)
{
    guint major = 0, minor = 0, micro = 0, nano = 0;
    int rc = 0;
    const char *extras[] = { "typefind", "decodebin", "audioconvert", "audioresample", NULL };
    int i;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    flush_print("HARNESS start pid=%d argc=%d\n", (int)getpid(), argc);
    print_mem("before_dlopen");

    flush_print("STEP dlopen libgstreamer-1.0.so.0\n");
    libgst = dlopen("libgstreamer-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!libgst) {
        flush_print("FAIL dlopen libgstreamer-1.0.so.0 (%s)\n", dlerror());
        return 3;
    }
    flush_print("OK dlopen libgstreamer-1.0.so.0\n");

    p_gst_init = must_dlsym("gst_init");
    p_gst_version = must_dlsym("gst_version");
    p_gst_version_string = must_dlsym("gst_version_string");
    p_gst_element_factory_find = must_dlsym("gst_element_factory_find");
    p_gst_plugin_feature_get_plugin_name = must_dlsym("gst_plugin_feature_get_plugin_name");
    p_gst_plugin_feature_get_plugin = must_dlsym("gst_plugin_feature_get_plugin");
    p_gst_plugin_get_filename = must_dlsym("gst_plugin_get_filename");
    p_gst_element_factory_make = must_dlsym("gst_element_factory_make");
    p_gst_object_unref = must_dlsym("gst_object_unref");
    p_gst_deinit = must_dlsym("gst_deinit");
    if (!p_gst_init || !p_gst_element_factory_make)
        return 4;

    print_mem("before_gst_init");
    flush_print("STEP gst_init\n");
    p_gst_init(&argc, &argv);
    if (p_gst_version)
        p_gst_version(&major, &minor, &micro, &nano);
    flush_print("OK gst_init version %u.%u.%u.%u (%s)\n",
                major, minor, micro, nano,
                p_gst_version_string ? p_gst_version_string() : "?");
    print_mem("after_gst_init");

    if (try_element("wavparse") != 0)
        rc = 1;
    print_mem("after_wavparse");

    for (i = 0; extras[i]; i++) {
        if (try_element(extras[i]) != 0 && rc == 0)
            rc = 2;
        print_mem(extras[i]);
    }

    if (p_gst_deinit) {
        flush_print("STEP gst_deinit\n");
        p_gst_deinit();
    }
    print_mem("after_gst_deinit");
    flush_print("HARNESS done rc=%d\n", rc);
    return rc;
}
