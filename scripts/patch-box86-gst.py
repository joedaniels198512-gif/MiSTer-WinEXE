#!/usr/bin/env python3
"""Port the minimum Box64 GStreamer class-bridge concepts into Box86.

Box86 gtkclass currently only knows GstObject and GstAllocator. Native ARM
GStreamer plugin registration (wavparse etc.) needs GstElement/GstBin/GstPad
and related type IDs wired the same way Box64 does, but with Box86's 32-bit
GType (int) and WRAPPER/FIND macros.

Class layouts match GStreamer 1.18.4 (SuperStation private runtime), not a
blind copy of current Box64 structs (e.g. GstTaskPool has no dispose_handle
in 1.18).
"""
from __future__ import annotations

import pathlib
import re
import sys

MARKER = "SS1_GST_CLASS_BRIDGE"

GST_CLASS_STRUCTS = r"""
/* """ + MARKER + r""" — GStreamer 1.18.4 class vtables for Box86 (32-bit). */
typedef struct my_GstTaskPoolClass_s {
    my_GstObjectClass_t parent_class;
    void (*prepare) (void* pool, void* error);
    void (*cleanup) (void* pool);
    void* (*push) (void* pool, void* func, void* user_data, void* error);
    void (*join) (void* pool, void* id);
    void* _gst_reserved[4];
} my_GstTaskPoolClass_t;

typedef struct my_GstElementClass_s {
    my_GstObjectClass_t parent_class;
    void* metadata;
    void* elementfactory;
    void* padtemplates;
    int numpadtemplates;
    uint32_t pad_templ_cookie;
    void (*pad_added) (void* element, void* pad);
    void (*pad_removed) (void* element, void* pad);
    void (*no_more_pads) (void* element);
    void* (*request_new_pad) (void* element, void* templ, void* name, void* caps);
    void (*release_pad) (void* element, void* pad);
    int (*get_state) (void* element, void* state, void* pending, uint64_t timeout);
    int (*set_state) (void* element, int state);
    int (*change_state) (void* element, int transition);
    void (*state_changed) (void* element, int oldstate, int newstate, int pending);
    void (*set_bus) (void* element, void* bus);
    void* (*provide_clock) (void* element);
    int (*set_clock) (void* element, void* clock);
    int (*send_event) (void* element, void* event);
    int (*query) (void* element, void* query);
    int (*post_message) (void* element, void* message);
    void (*set_context) (void* element, void* context);
    void* _gst_reserved[20-2];
} my_GstElementClass_t;

typedef struct my_GstBinClass_s {
    my_GstElementClass_t parent_class;
    void* pool;
    void (*element_added) (void* bin, void* child);
    void (*element_removed) (void* bin, void* child);
    int (*add_element) (void* bin, void* element);
    int (*remove_element) (void* bin, void* element);
    void (*handle_message) (void* bin, void* message);
    int (*do_latency) (void* bin);
    void (*deep_element_added) (void* bin, void* sub_bin, void* child);
    void (*deep_element_removed) (void* bin, void* sub_bin, void* child);
    void* _gst_reserved[4-2];
} my_GstBinClass_t;

typedef struct my_GstPadClass_s {
    my_GstObjectClass_t parent_class;
    void (*linked) (void* pad, void* peer);
    void (*unlinked) (void* pad, void* peer);
    void* _gst_reserved[4];
} my_GstPadClass_t;

typedef struct my_GstBufferPoolClass_s {
    my_GstObjectClass_t object_class;
    void* (*get_options) (void* pool);
    int (*set_config) (void* pool, void* config);
    int (*start) (void* pool);
    int (*stop) (void* pool);
    int (*acquire_buffer) (void* pool, void* buffer, void* params);
    int (*alloc_buffer) (void* pool, void* buffer, void* params);
    void (*reset_buffer) (void* pool, void* buffer);
    void (*release_buffer) (void* pool, void* buffer);
    void (*free_buffer) (void* pool, void* buffer);
    void (*flush_start) (void* pool);
    void (*flush_stop) (void* pool);
    void* _gst_reserved[4-2];
} my_GstBufferPoolClass_t;

typedef struct my_GTypeInterface_s {
    int g_type;
    int g_instance_type;
} my_GTypeInterface_t;

typedef struct my_GstURIHandlerInterface_s {
    my_GTypeInterface_t parent;
    int (*get_type) (unsigned long type);
    void* (*get_protocols) (unsigned long type);
    void* (*get_uri) (void* handler);
    int (*set_uri) (void* handler, void* uri, void* error);
} my_GstURIHandlerInterface_t;
typedef my_GstURIHandlerInterface_t my_GstURIHandlerClass_t;

"""

GST_WRAP_FUNCS = r"""
// ----- GstTaskPoolClass (""" + MARKER + r""") ------
WRAPPER(GstTaskPool, prepare, void,  (void* pool, void* error), "pp", pool, error);
WRAPPER(GstTaskPool, cleanup, void,  (void* pool), "p", pool);
WRAPPER(GstTaskPool, push, void*,    (void* pool, void* func, void* user_data, void* error), "pppp", pool, func, user_data, error);
WRAPPER(GstTaskPool, join, void,     (void* pool, void* id), "pp", pool, id);

#define SUPERGO()               \
    GO(prepare, vFpp);          \
    GO(cleanup, vFp);           \
    GO(push, pFpppp);           \
    GO(join, vFpp);             \

static void wrapGstTaskPoolClass(my_GstTaskPoolClass_t* class)
{
    wrapGstObjectClass(&class->parent_class);
    #define GO(A, W) class->A = reverse_##A##_GstTaskPool (W, class->A)
    SUPERGO()
    #undef GO
}
static void unwrapGstTaskPoolClass(my_GstTaskPoolClass_t* class)
{
    unwrapGstObjectClass(&class->parent_class);
    #define GO(A, W)   class->A = find_##A##_GstTaskPool (class->A)
    SUPERGO()
    #undef GO
}
static void bridgeGstTaskPoolClass(my_GstTaskPoolClass_t* class)
{
    bridgeGstObjectClass(&class->parent_class);
    #define GO(A, W) autobridge_##A##_GstTaskPool (W, class->A)
    SUPERGO()
    #undef GO
}
#undef SUPERGO

// ----- GstElementClass ------
WRAPPER(GstElement,pad_added, void, (void* element, void* pad), "pp", element, pad);
WRAPPER(GstElement,pad_removed, void, (void* element, void* pad), "pp", element, pad);
WRAPPER(GstElement,no_more_pads, void, (void* element), "p", element);
WRAPPER(GstElement,request_new_pad, void*, (void* element, void* templ, void* name, void* caps), "pppp", element, templ, name, caps);
WRAPPER(GstElement,release_pad, void, (void* element, void* pad), "pp", element, pad);
WRAPPER(GstElement,get_state, int, (void*  element, void* state, void* pending, uint64_t timeout), "pppU", element, state, pending, timeout);
WRAPPER(GstElement,set_state, int, (void* element, int state), "pi", element, state);
WRAPPER(GstElement,change_state, int, (void* element, int transition), "pi", element, transition);
WRAPPER(GstElement,state_changed, void, (void* element, int oldstate, int newstate, int pending), "piii", element, oldstate, newstate, pending);
WRAPPER(GstElement,set_bus, void, (void*  element, void* bus), "pp", element, bus);
WRAPPER(GstElement,provide_clock, void*, (void* element), "p", element);
WRAPPER(GstElement,set_clock, int, (void* element, void* clock), "pp", element, clock);
WRAPPER(GstElement,send_event, int, (void* element, void* event), "pp", element, event);
WRAPPER(GstElement,query, int, (void* element, void* query), "pp", element, query);
WRAPPER(GstElement,post_message, int, (void* element, void* message), "pp", element, message);
WRAPPER(GstElement,set_context, void, (void* element, void* context), "pp", element, context);

#define SUPERGO()               \
    GO(pad_added, vFpp);        \
    GO(pad_removed, vFpp);      \
    GO(no_more_pads, vFp);      \
    GO(request_new_pad, pFpppp);\
    GO(release_pad, vFpp);      \
    GO(get_state, iFpppU);      \
    GO(set_state, iFpi);        \
    GO(change_state, iFpi);     \
    GO(state_changed, vFpiii);  \
    GO(set_bus, vFpp);          \
    GO(provide_clock, pFp);     \
    GO(set_clock, iFpp);        \
    GO(send_event, iFpp);       \
    GO(query, iFpp);            \
    GO(post_message, iFpp);     \
    GO(set_context, vFpp);      \

static void wrapGstElementClass(my_GstElementClass_t* class)
{
    wrapGstObjectClass(&class->parent_class);
    #define GO(A, W) class->A = reverse_##A##_GstElement (W, class->A)
    SUPERGO()
    #undef GO
}
static void unwrapGstElementClass(my_GstElementClass_t* class)
{
    unwrapGstObjectClass(&class->parent_class);
    #define GO(A, W)   class->A = find_##A##_GstElement (class->A)
    SUPERGO()
    #undef GO
}
static void bridgeGstElementClass(my_GstElementClass_t* class)
{
    bridgeGstObjectClass(&class->parent_class);
    #define GO(A, W) autobridge_##A##_GstElement (W, class->A)
    SUPERGO()
    #undef GO
}
#undef SUPERGO

// ----- GstBinClass ------
WRAPPER(GstBin,element_added, void, (void* bin, void* child), "pp", bin, child);
WRAPPER(GstBin,element_removed, void, (void* bin, void* child), "pp", bin, child);
WRAPPER(GstBin,add_element, int, (void* bin, void* element), "pp", bin, element);
WRAPPER(GstBin,remove_element, int, (void* bin, void* element), "pp", bin, element);
WRAPPER(GstBin,handle_message, void, (void* bin, void* message), "pp", bin, message);
WRAPPER(GstBin,do_latency, int, (void* bin), "p", bin);
WRAPPER(GstBin,deep_element_added, void, (void* bin, void* sub_bin, void* child), "ppp", bin, sub_bin, child);
WRAPPER(GstBin,deep_element_removed, void, (void* bin, void* sub_bin, void* child), "ppp", bin, sub_bin, child);

#define SUPERGO()                   \
    GO(element_added, vFpp);        \
    GO(element_removed, vFpp);      \
    GO(add_element, iFpp);          \
    GO(remove_element, iFpp);       \
    GO(handle_message, vFpp);       \
    GO(do_latency, iFp);            \
    GO(deep_element_added, vFppp);  \
    GO(deep_element_removed, vFppp);\

static void wrapGstBinClass(my_GstBinClass_t* class)
{
    wrapGstElementClass(&class->parent_class);
    #define GO(A, W) class->A = reverse_##A##_GstBin (W, class->A)
    SUPERGO()
    #undef GO
}
static void unwrapGstBinClass(my_GstBinClass_t* class)
{
    unwrapGstElementClass(&class->parent_class);
    #define GO(A, W)   class->A = find_##A##_GstBin (class->A)
    SUPERGO()
    #undef GO
}
static void bridgeGstBinClass(my_GstBinClass_t* class)
{
    bridgeGstElementClass(&class->parent_class);
    #define GO(A, W) autobridge_##A##_GstBin (W, class->A)
    SUPERGO()
    #undef GO
}
#undef SUPERGO

// ----- GstPadClass ------
WRAPPER(GstPad, linked, void, (void* pad, void* peer), "pp", pad, peer);
WRAPPER(GstPad, unlinked, void, (void* pad, void* peer), "pp", pad, peer);

#define SUPERGO()               \
    GO(linked, vFpp);           \
    GO(unlinked, vFpp);         \

static void wrapGstPadClass(my_GstPadClass_t* class)
{
    wrapGstObjectClass(&class->parent_class);
    #define GO(A, W) class->A = reverse_##A##_GstPad (W, class->A)
    SUPERGO()
    #undef GO
}
static void unwrapGstPadClass(my_GstPadClass_t* class)
{
    unwrapGstObjectClass(&class->parent_class);
    #define GO(A, W)   class->A = find_##A##_GstPad (class->A)
    SUPERGO()
    #undef GO
}
static void bridgeGstPadClass(my_GstPadClass_t* class)
{
    bridgeGstObjectClass(&class->parent_class);
    #define GO(A, W) autobridge_##A##_GstPad (W, class->A)
    SUPERGO()
    #undef GO
}
#undef SUPERGO

// ----- GstBufferPoolClass ------
WRAPPER(GstBufferPool, get_options, void*,(void* pool), "p", pool);
WRAPPER(GstBufferPool, set_config, int ,(void* pool, void* config), "pp", pool, config);
WRAPPER(GstBufferPool, start, int ,(void* pool), "p", pool);
WRAPPER(GstBufferPool, stop, int ,(void* pool), "p", pool);
WRAPPER(GstBufferPool, acquire_buffer, int ,(void* pool, void* buffer, void* params), "ppp", pool, buffer, params);
WRAPPER(GstBufferPool, alloc_buffer, int ,(void* pool, void* buffer, void* params), "ppp", pool, buffer, params);
WRAPPER(GstBufferPool, reset_buffer, void ,(void* pool, void* buffer), "pp", pool, buffer);
WRAPPER(GstBufferPool, release_buffer, void ,(void* pool, void* buffer), "pp", pool, buffer);
WRAPPER(GstBufferPool, free_buffer, void ,(void* pool, void* buffer), "pp", pool, buffer);
WRAPPER(GstBufferPool, flush_start, void ,(void* pool), "p", pool);
WRAPPER(GstBufferPool, flush_stop, void ,(void* pool), "p", pool);

#define SUPERGO()               \
    GO(get_options, pFp);       \
    GO(set_config, iFpp);       \
    GO(start, iFp);             \
    GO(stop, iFp);              \
    GO(acquire_buffer, iFppp);  \
    GO(alloc_buffer, iFppp);    \
    GO(reset_buffer, vFpp);     \
    GO(release_buffer, vFpp);   \
    GO(free_buffer, vFpp);      \
    GO(flush_start, vFp);       \
    GO(flush_stop, vFp);        \

static void wrapGstBufferPoolClass(my_GstBufferPoolClass_t* class)
{
    wrapGstObjectClass(&class->object_class);
    #define GO(A, W) class->A = reverse_##A##_GstBufferPool (W, class->A)
    SUPERGO()
    #undef GO
}
static void unwrapGstBufferPoolClass(my_GstBufferPoolClass_t* class)
{
    unwrapGstObjectClass(&class->object_class);
    #define GO(A, W)   class->A = find_##A##_GstBufferPool (class->A)
    SUPERGO()
    #undef GO
}
static void bridgeGstBufferPoolClass(my_GstBufferPoolClass_t* class)
{
    bridgeGstObjectClass(&class->object_class);
    #define GO(A, W) autobridge_##A##_GstBufferPool (W, class->A)
    SUPERGO()
    #undef GO
}
#undef SUPERGO

// ----- GstURIHandlerInterface (exposed as GstURIHandlerClass for GTKCLASS) ------
WRAPPER(GstURIHandler,get_type, int, (unsigned long type), "L", type);
WRAPPER(GstURIHandler,get_protocols, void*, (unsigned long type), "L", type);
WRAPPER(GstURIHandler,get_uri, void*, (void* handler), "p", handler);
WRAPPER(GstURIHandler,set_uri, int, (void* handler, void* uri, void* error), "ppp", handler, uri, error);

#define SUPERGO()                       \
    GO(get_type, iFL);                  \
    GO(get_protocols, pFL);             \
    GO(get_uri, pFp);                   \
    GO(set_uri, iFppp);                 \

static void wrapGstURIHandlerClass(my_GstURIHandlerClass_t* iface)
{
    #define GO(A, W) iface->A = reverse_##A##_GstURIHandler (W, iface->A)
    SUPERGO()
    #undef GO
}
static void unwrapGstURIHandlerClass(my_GstURIHandlerClass_t* iface)
{
    #define GO(A, W)   iface->A = find_##A##_GstURIHandler (iface->A)
    SUPERGO()
    #undef GO
}
static void bridgeGstURIHandlerClass(my_GstURIHandlerClass_t* iface)
{
    #define GO(A, W) autobridge_##A##_GstURIHandler (W, iface->A)
    SUPERGO()
    #undef GO
}
#undef SUPERGO

"""

PLUGIN_GO_ENABLE = [
    ("//GO(gst_plugin_feature_get_plugin, ", "GO(gst_plugin_feature_get_plugin, pFp)"),
    ("//GO(gst_plugin_feature_get_plugin_name, ", "GO(gst_plugin_feature_get_plugin_name, pFp)"),
    ("//GO(gst_plugin_feature_load, ", "GO(gst_plugin_feature_load, pFp)"),
    ("//GO(gst_plugin_get_filename, ", "GO(gst_plugin_get_filename, pFp)"),
    ("//GO(gst_plugin_get_name, ", "GO(gst_plugin_get_name, pFp)"),
    ("//GO(gst_plugin_get_type, ", "GO(gst_plugin_get_type, pFv)"),
    ("//GO(gst_plugin_is_loaded, ", "GO(gst_plugin_is_loaded, iFp)"),
    ("//GO(gst_plugin_load, ", "GO(gst_plugin_load, pFp)"),
    ("//GO(gst_plugin_load_by_name, ", "GO(gst_plugin_load_by_name, pFp)"),
    ("//GO(gst_buffer_pool_get_type, ", "GO(gst_buffer_pool_get_type, pFv)"),
    ("//GO(gst_task_pool_get_type, ", "GO(gst_task_pool_get_type, pFv)"),
    ("//GO(gst_uri_handler_get_type, ", "GO(gst_uri_handler_get_type, pFv)"),
]


def must_replace(text: str, old: str, new: str, where: str) -> str:
    if old not in text:
        raise SystemExit(f"{where}: expected snippet not found:\n{old[:120]}")
    return text.replace(old, new, 1)


def patch_gtkclass_h(path: pathlib.Path) -> None:
    text = path.read_text()
    if MARKER in text:
        print(f"skip {path} (already patched)")
        return
    text = must_replace(
        text,
        "} my_GstAllocatorClass_t;\n\n// GTypeValueTable",
        "} my_GstAllocatorClass_t;\n" + GST_CLASS_STRUCTS + "// GTypeValueTable",
        str(path),
    )
    text2, n = re.subn(
        r"GTKCLASS\(GstAllocator\)(\s*\\\n)",
        "GTKCLASS(GstAllocator)\\1"
        "GTKCLASS(GstTaskPool)\\1"
        "GTKCLASS(GstElement)\\1"
        "GTKCLASS(GstBin)\\1"
        "GTKCLASS(GstPad)\\1"
        "GTKCLASS(GstBufferPool)\\1"
        "GTKCLASS(GstURIHandler)\\1",
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit(f"{path}: GTKCLASS(GstAllocator) not found")
    text = text2
    path.write_text(text)
    print(f"patched {path}")


def patch_gtkclass_c(path: pathlib.Path) -> None:
    text = path.read_text()
    if MARKER in text:
        print(f"skip {path} (already patched)")
        return
    needle = "// No more wrap/unwrap\n#undef WRAPPER"
    text = must_replace(text, needle, GST_WRAP_FUNCS + needle, str(path))
    path.write_text(text)
    print(f"patched {path}")


def patch_wrappedgstreamer_c(path: pathlib.Path) -> None:
    text = path.read_text()
    if "SetGstElementID" in text:
        print(f"skip {path} (already patched)")
        return
    text = must_replace(
        text,
        """#define ADDED_FUNCTIONS()                   \\
    GO(gst_object_get_type, LFv_t)          \\
    GO(gst_allocator_get_type, LFv_t)       \\
    GO(gst_structure_new_empty, pFp_t)      \\
""",
        """#define ADDED_FUNCTIONS()                   \\
    GO(gst_object_get_type, LFv_t)          \\
    GO(gst_allocator_get_type, LFv_t)       \\
    GO(gst_task_pool_get_type, LFv_t)       \\
    GO(gst_element_get_type, LFv_t)         \\
    GO(gst_bin_get_type, LFv_t)             \\
    GO(gst_pad_get_type, LFv_t)             \\
    GO(gst_uri_handler_get_type, LFv_t)     \\
    GO(gst_buffer_pool_get_type, LFv_t)     \\
    GO(gst_structure_new_empty, pFp_t)      \\
""",
        str(path),
    )
    extra = """        SetGstTaskPoolID(my->gst_task_pool_get_type());            \\
        SetGstElementID(my->gst_element_get_type());                \\
        SetGstBinID(my->gst_bin_get_type());                        \\
        SetGstPadID(my->gst_pad_get_type());                        \\
        SetGstURIHandlerID(my->gst_uri_handler_get_type());         \\
        SetGstBufferPoolID(my->gst_buffer_pool_get_type());         \\
"""
    text = must_replace(
        text,
        "        SetGstAllocatorID(my->gst_allocator_get_type());           \\\n        setNeededLibs(lib, 1, \"libgtk-3.so\");",
        "        SetGstAllocatorID(my->gst_allocator_get_type());           \\\n"
        + extra
        + "        setNeededLibs(lib, 1, \"libgtk-3.so\");",
        str(path),
    )
    text = must_replace(
        text,
        "        SetGstAllocatorID(my->gst_allocator_get_type());           \\\n        setNeededLibs(lib, 1, \"libgtk-3.so.0\");",
        "        SetGstAllocatorID(my->gst_allocator_get_type());           \\\n"
        + extra
        + "        setNeededLibs(lib, 1, \"libgtk-3.so.0\");",
        str(path),
    )
    path.write_text(text)
    print(f"patched {path}")


def patch_private_h(path: pathlib.Path) -> None:
    text = path.read_text()
    if "GO(gst_plugin_feature_get_plugin, pFp)" in text:
        print(f"skip {path} (already patched)")
        return
    lines = text.splitlines(True)
    out = []
    replaced = set()
    for line in lines:
        done = False
        for prefix, replacement in PLUGIN_GO_ENABLE:
            if line.startswith(prefix):
                out.append(replacement + "\n")
                replaced.add(prefix)
                done = True
                break
        if not done:
            out.append(line)
    missing = [p for p, _ in PLUGIN_GO_ENABLE if p not in replaced]
    if missing:
        raise SystemExit(f"{path}: did not replace {missing}")
    path.write_text("".join(out))
    print(f"patched {path}")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} /path/to/box86", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    patch_gtkclass_h(root / "src/include/gtkclass.h")
    patch_gtkclass_c(root / "src/tools/gtkclass.c")
    patch_wrappedgstreamer_c(root / "src/wrapped/wrappedgstreamer.c")
    patch_private_h(root / "src/wrapped/wrappedgstreamer_private.h")
    print("box86 gstreamer class-bridge patch complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
