/* Tiny i386 Linux GStreamer harness for Box86 (no Wine, no X11, no audio).
 *
 * Cross-compile as a 32-bit ELF against GStreamer 1.18 (Bullseye), then run:
 *   box86 ss1-gst-harness
 * with the private ARMHF GStreamer LD_LIBRARY_PATH / GST_* env.
 */
#include <gst/gst.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>

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

static int try_element(const char *name)
{
    GstElementFactory *factory;
    GstPlugin *plugin;
    GstElement *el;
    const gchar *filename;
    const gchar *plugin_name;

    flush_print("STEP factory_find %s\n", name);
    factory = gst_element_factory_find(name);
    if (!factory) {
        flush_print("FAIL factory_find %s (NULL)\n", name);
        return 1;
    }

    plugin_name = gst_plugin_feature_get_plugin_name(GST_PLUGIN_FEATURE(factory));
    plugin = gst_plugin_feature_get_plugin(GST_PLUGIN_FEATURE(factory));
    filename = plugin ? gst_plugin_get_filename(plugin) : NULL;
    flush_print("OK factory_find %s plugin=%s filename=%s\n",
                name,
                plugin_name ? plugin_name : "(null)",
                filename ? filename : "(null)");
    if (plugin)
        gst_object_unref(plugin);

    flush_print("STEP factory_make %s\n", name);
    el = gst_element_factory_make(name, NULL);
    if (!el) {
        flush_print("FAIL factory_make %s\n", name);
        gst_object_unref(factory);
        return 1;
    }
    flush_print("OK factory_make %s type=%s\n", name, G_OBJECT_TYPE_NAME(el));
    gst_object_unref(el);
    gst_object_unref(factory);
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
    print_mem("before_gst_init");

    flush_print("STEP gst_init\n");
    gst_init(&argc, &argv);
    gst_version(&major, &minor, &micro, &nano);
    flush_print("OK gst_init version %u.%u.%u.%u (%s)\n",
                major, minor, micro, nano, gst_version_string());
    print_mem("after_gst_init");

    if (try_element("wavparse") != 0)
        rc = 1;
    print_mem("after_wavparse");

    for (i = 0; extras[i]; i++) {
        if (try_element(extras[i]) != 0 && rc == 0)
            rc = 2;
        print_mem(extras[i]);
    }

    flush_print("STEP gst_deinit\n");
    gst_deinit();
    print_mem("after_gst_deinit");
    flush_print("HARNESS done rc=%d\n", rc);
    return rc;
}
