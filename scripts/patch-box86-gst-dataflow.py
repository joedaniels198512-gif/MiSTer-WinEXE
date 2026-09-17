#!/usr/bin/env python3
"""Phase 2 Box86 GStreamer dataflow bridge: GstBaseSrc/PushSrc/BaseSink + GstPad instance.

Applied after patch-box86-gst.py. Layouts match GStreamer 1.18.4 on 32-bit ARM
(GLib 2.66), not a blind copy of Box64 64-bit structs.
"""
from __future__ import annotations

import pathlib
import re
import sys

MARKER = "SS1_GST_DATAFLOW"

STRUCTS = r"""
/* """ + MARKER + r""" — 32-bit GStreamer 1.18.4 instance/class layouts. */
typedef union my_GMutex_u {
    void* p;
    uint32_t i[2];
} my_GMutex_t;

typedef struct my_GCond_s {
    void* p;
    uint32_t i[2];
} my_GCond_t;

typedef struct my_GRecMutex_s {
    void* p;
    uint32_t i[2];
} my_GRecMutex_t;

typedef struct my_GHookList_s {
    unsigned long seq_id;
    uint32_t hook_size_setup;
    void* hooks;
    void* dummy3;
    void (*finalize_hook) (void* hook_list, void* hook);
    void* dummy[2];
} my_GHookList_t;

typedef struct my_GObjectInst_s {
    void* g_class;
    uint32_t ref_count;
    void* qdata;
} my_GObjectInst_t;

typedef struct my_GstObjectInst_s {
    my_GObjectInst_t object;
    my_GMutex_t lock;
    char* name;
    void* parent;
    uint32_t flags;
    void* control_bindings;
    uint64_t control_rate;
    uint64_t last_sync;
    void* _gst_reserved;
} my_GstObjectInst_t;

typedef struct my_GstElementInst_s {
    my_GstObjectInst_t parent;
} my_GstElementInst_t;

typedef struct my_GstBaseSrc_s {
    my_GstElementInst_t parent;
} my_GstBaseSrc_t;

typedef struct my_GstPushSrc_s {
    my_GstBaseSrc_t parent;
} my_GstPushSrc_t;

typedef struct my_GstBaseSink_s {
    my_GstElementInst_t parent;
} my_GstBaseSink_t;

typedef struct my_GstPad_s {
    my_GstObjectInst_t object;
    void* element_private;
    void* padtemplate;
    int direction;
    my_GRecMutex_t stream_rec_lock;
    void* task;
    my_GCond_t block_cond;
    my_GHookList_t probes;
    int mode;
    int (*activatefunc) (void* pad, void* parent);
    void* activatedata;
    void (*activatenotify) (void* a);
    int (*activatemodefunc) (void* pad, void* parent, int mode, int active);
    void* activatemodedata;
    void (*activatemodenotify) (void* a);
    void* peer;
    int (*linkfunc) (void* pad, void* parent, void* peer);
    void* linkdata;
    void (*linknotify) (void* a);
    void (*unlinkfunc) (void* pad, void* parent);
    void* unlinkdata;
    void (*unlinknotify) (void* a);
    int (*chainfunc) (void* pad, void* parent, void* buffer);
    void* chaindata;
    void (*chainnotify) (void* a);
    int (*chainlistfunc) (void* pad, void* parent, void* list);
    void* chainlistdata;
    void (*chainlistnotify) (void* a);
    int (*getrangefunc) (void* pad, void* parent, uint64_t offset, uint32_t length, void* buffer);
    void* getrangedata;
    void (*getrangenotify) (void* a);
    int (*eventfunc) (void* pad, void* parent, void* event);
    void* eventdata;
    void (*eventnotify) (void* a);
    int64_t offset;
    int (*queryfunc) (void* pad, void* parent, void* query);
    void* querydata;
    void (*querynotify) (void* a);
    void* (*iterintlinkfunc) (void* pad, void* parent);
    void* iterintlinkdata;
    void (*iterintlinknotify) (void* a);
    int num_probes;
    int num_blocked;
    void* priv;
    union {
        void* _gst_reserved[4];
        struct {
            int last_flowret;
            int (*eventfullfunc) (void* pad, void* parent, void* event);
        } abi;
    } ABI;
} my_GstPad_t;

typedef struct my_GstBaseSrcClass_s {
    my_GstElementClass_t parent_class;
    void* (*get_caps) (void* src, void* filter);
    int (*negotiate) (void* src);
    void* (*fixate) (void* src, void* caps);
    int (*set_caps) (void* src, void* caps);
    int (*decide_allocation) (void* src, void* query);
    int (*start) (void* src);
    int (*stop) (void* src);
    void (*get_times) (void* src, void* buffer, void* start, void* end);
    int (*get_size) (void* src, void* size);
    int (*is_seekable) (void* src);
    int (*prepare_seek_segment) (void* src, void* seek, void* segment);
    int (*do_seek) (void* src, void* segment);
    int (*unlock) (void* src);
    int (*unlock_stop) (void* src);
    int (*query) (void* src, void* query);
    int (*event) (void* src, void* event);
    int (*create) (void* src, uint64_t offset, uint32_t size, void* buf);
    int (*alloc) (void* src, uint64_t offset, uint32_t size, void* buf);
    int (*fill) (void* src, uint64_t offset, uint32_t size, void* buf);
    void* _gst_reserved[20];
} my_GstBaseSrcClass_t;

typedef struct my_GstPushSrcClass_s {
    my_GstBaseSrcClass_t parent_class;
    int (*create) (void* src, void* buf);
    int (*alloc) (void* src, void* buf);
    int (*fill) (void* src, void* buf);
    void* _gst_reserved[4];
} my_GstPushSrcClass_t;

typedef struct my_GstBaseSinkClass_s {
    my_GstElementClass_t parent_class;
    void* (*get_caps) (void* sink, void* filter);
    int (*set_caps) (void* sink, void* caps);
    void* (*fixate) (void* sink, void* caps);
    int (*activate_pull) (void* sink, int active);
    void (*get_times) (void* sink, void* buffer, void* start, void* end);
    int (*propose_allocation) (void* sink, void* query);
    int (*start) (void* sink);
    int (*stop) (void* sink);
    int (*unlock) (void* sink);
    int (*unlock_stop) (void* sink);
    int (*query) (void* sink, void* query);
    int (*event) (void* sink, void* event);
    int (*wait_event) (void* sink, void* event);
    int (*prepare) (void* sink, void* buffer);
    int (*prepare_list) (void* sink, void* buffer_list);
    int (*preroll) (void* sink, void* buffer);
    int (*render) (void* sink, void* buffer);
    int (*render_list) (void* sink, void* buffer_list);
    void* _gst_reserved[20];
} my_GstBaseSinkClass_t;

"""

WRAP = r"""
// ----- GstBaseSrcClass (""" + MARKER + r""") ------
WRAPPER(GstBaseSrc, get_caps, void*, (void* src, void* filter), "pp", src, filter);
WRAPPER(GstBaseSrc, negotiate, int, (void* src), "p", src);
WRAPPER(GstBaseSrc, fixate, void*, (void* src, void* caps), "pp", src, caps);
WRAPPER(GstBaseSrc, set_caps, int, (void* src, void* caps), "pp", src, caps);
WRAPPER(GstBaseSrc, decide_allocation, int, (void* src, void* query), "pp", src, query);
WRAPPER(GstBaseSrc, start, int, (void* src), "p", src);
WRAPPER(GstBaseSrc, stop, int, (void* src), "p", src);
WRAPPER(GstBaseSrc, get_times, void , (void* src, void* buffer, void* start, void* end), "pppp", src, buffer, start, end);
WRAPPER(GstBaseSrc, get_size, int, (void* src, void* size), "pp", src, size);
WRAPPER(GstBaseSrc, is_seekable, int, (void* src), "p", src);
WRAPPER(GstBaseSrc, prepare_seek_segment, int, (void* src, void* seek, void* segment), "ppp", src, seek, segment);
WRAPPER(GstBaseSrc, do_seek, int, (void* src, void* segment), "pp", src, segment);
WRAPPER(GstBaseSrc, unlock, int, (void* src), "p", src);
WRAPPER(GstBaseSrc, unlock_stop, int, (void* src), "p", src);
WRAPPER(GstBaseSrc, query, int, (void* src, void* query), "pp", src, query);
WRAPPER(GstBaseSrc, event, int, (void* src, void* event), "pp", src, event);
WRAPPER(GstBaseSrc, create, int, (void* src, uint64_t offset, uint32_t size, void* buf), "pUup", src, offset, size, buf);
WRAPPER(GstBaseSrc, alloc, int, (void* src, uint64_t offset, uint32_t size, void* buf), "pUup", src, offset, size, buf);
WRAPPER(GstBaseSrc, fill, int, (void* src, uint64_t offset, uint32_t size, void* buf), "pUup", src, offset, size, buf);

#define SUPERGO()                       \
    GO(get_caps, pFpp);                 \
    GO(negotiate, iFp);                 \
    GO(fixate, pFpp);                   \
    GO(set_caps, iFpp);                 \
    GO(decide_allocation, iFpp);        \
    GO(start, iFp);                     \
    GO(stop, iFp);                      \
    GO(get_times, vFpppp);              \
    GO(get_size, iFpp);                 \
    GO(is_seekable, iFp);               \
    GO(prepare_seek_segment, iFppp);    \
    GO(do_seek, iFpp);                  \
    GO(unlock, iFp);                    \
    GO(unlock_stop, iFp);               \
    GO(query, iFpp);                    \
    GO(event, iFpp);                    \
    GO(create, iFpUup);                 \
    GO(alloc, iFpUup);                  \
    GO(fill, iFpUup);                   \

static void wrapGstBaseSrcClass(my_GstBaseSrcClass_t* class)
{
    wrapGstElementClass(&class->parent_class);
    #define GO(A, W) class->A = reverse_##A##_GstBaseSrc (W, class->A)
    SUPERGO()
    #undef GO
}
static void unwrapGstBaseSrcClass(my_GstBaseSrcClass_t* class)
{
    unwrapGstElementClass(&class->parent_class);
    #define GO(A, W)   class->A = find_##A##_GstBaseSrc (class->A)
    SUPERGO()
    #undef GO
}
static void bridgeGstBaseSrcClass(my_GstBaseSrcClass_t* class)
{
    bridgeGstElementClass(&class->parent_class);
    #define GO(A, W) autobridge_##A##_GstBaseSrc (W, class->A)
    SUPERGO()
    #undef GO
}
#undef SUPERGO

// ----- GstPushSrcClass ------
WRAPPER(GstPushSrc, create, int, (void* src, void* buf), "pp", src, buf);
WRAPPER(GstPushSrc, alloc, int, (void* src, void* buf), "pp", src, buf);
WRAPPER(GstPushSrc, fill, int, (void* src, void* buf), "pp", src, buf);

#define SUPERGO()               \
    GO(create, iFpp);           \
    GO(alloc, iFpp);            \
    GO(fill, iFpp);             \

static void wrapGstPushSrcClass(my_GstPushSrcClass_t* class)
{
    wrapGstBaseSrcClass(&class->parent_class);
    #define GO(A, W) class->A = reverse_##A##_GstPushSrc (W, class->A)
    SUPERGO()
    #undef GO
}
static void unwrapGstPushSrcClass(my_GstPushSrcClass_t* class)
{
    unwrapGstBaseSrcClass(&class->parent_class);
    #define GO(A, W)   class->A = find_##A##_GstPushSrc (class->A)
    SUPERGO()
    #undef GO
}
static void bridgeGstPushSrcClass(my_GstPushSrcClass_t* class)
{
    bridgeGstBaseSrcClass(&class->parent_class);
    #define GO(A, W) autobridge_##A##_GstPushSrc (W, class->A)
    SUPERGO()
    #undef GO
}
#undef SUPERGO

// ----- GstBaseSinkClass ------
WRAPPER(GstBaseSink, get_caps, void*, (void* sink, void* filter), "pp", sink, filter);
WRAPPER(GstBaseSink, set_caps, int, (void* sink, void* caps), "pp", sink, caps);
WRAPPER(GstBaseSink, fixate, void* , (void* sink, void* caps), "pp", sink, caps);
WRAPPER(GstBaseSink, activate_pull, int, (void* sink, int active), "pi", sink, active);
WRAPPER(GstBaseSink, get_times, void, (void* sink, void* buffer, void* start, void* end), "pppp", sink, buffer, start, end);
WRAPPER(GstBaseSink, propose_allocation, int, (void* sink, void* query), "pp", sink, query);
WRAPPER(GstBaseSink, start, int, (void* sink), "p", sink);
WRAPPER(GstBaseSink, stop, int, (void* sink), "p", sink);
WRAPPER(GstBaseSink, unlock, int, (void* sink), "p", sink);
WRAPPER(GstBaseSink, unlock_stop, int, (void* sink), "p", sink);
WRAPPER(GstBaseSink, query, int, (void* sink, void* query), "pp", sink, query);
WRAPPER(GstBaseSink, event, int, (void* sink, void* event), "pp", sink, event);
WRAPPER(GstBaseSink, wait_event, int, (void* sink, void* event), "pp", sink, event);
WRAPPER(GstBaseSink, prepare, int, (void* sink, void* buffer), "pp", sink, buffer);
WRAPPER(GstBaseSink, prepare_list, int, (void* sink, void* buffer_list), "pp", sink, buffer_list);
WRAPPER(GstBaseSink, preroll, int, (void* sink, void* buffer), "pp", sink, buffer);
WRAPPER(GstBaseSink, render, int, (void* sink, void* buffer), "pp", sink, buffer);
WRAPPER(GstBaseSink, render_list, int, (void* sink, void* buffer_list), "pp", sink, buffer_list);

#define SUPERGO()                       \
    GO(get_caps, pFpp);                 \
    GO(set_caps, iFpp);                 \
    GO(fixate, pFpp);                   \
    GO(activate_pull, iFpi);            \
    GO(get_times, vFpppp);              \
    GO(propose_allocation, iFpp);       \
    GO(start, iFp);                     \
    GO(stop, iFp);                      \
    GO(unlock, iFp);                    \
    GO(unlock_stop, iFp);               \
    GO(query, iFpp);                    \
    GO(event, iFpp);                    \
    GO(wait_event, iFpp);               \
    GO(prepare, iFpp);                  \
    GO(prepare_list, iFpp);             \
    GO(preroll, iFpp);                  \
    GO(render, iFpp);                   \
    GO(render_list, iFpp);              \

static void wrapGstBaseSinkClass(my_GstBaseSinkClass_t* class)
{
    wrapGstElementClass(&class->parent_class);
    #define GO(A, W) class->A = reverse_##A##_GstBaseSink (W, class->A)
    SUPERGO()
    #undef GO
}
static void unwrapGstBaseSinkClass(my_GstBaseSinkClass_t* class)
{
    unwrapGstElementClass(&class->parent_class);
    #define GO(A, W)   class->A = find_##A##_GstBaseSink (class->A)
    SUPERGO()
    #undef GO
}
static void bridgeGstBaseSinkClass(my_GstBaseSinkClass_t* class)
{
    bridgeGstElementClass(&class->parent_class);
    #define GO(A, W) autobridge_##A##_GstBaseSink (W, class->A)
    SUPERGO()
    #undef GO
}
#undef SUPERGO

// ----- GstPad instance callbacks ------
WRAPPER(GstPadInstance, activatefunc, int    , (void* pad, void* parent), "pp", pad, parent);
WRAPPER(GstPadInstance, activatenotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, activatemodefunc, int    , (void* pad, void* parent, int mode, int active), "ppii", pad, parent, mode, active);
WRAPPER(GstPadInstance, activatemodenotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, linkfunc, int    , (void* pad, void* parent, void* peer), "ppp", pad, parent, peer);
WRAPPER(GstPadInstance, linknotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, unlinkfunc, void   , (void* pad, void* parent), "pp", pad, parent);
WRAPPER(GstPadInstance, unlinknotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, chainfunc, int    , (void* pad, void* parent, void* buffer), "ppp", pad, parent, buffer);
WRAPPER(GstPadInstance, chainnotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, chainlistfunc, int    , (void* pad, void* parent, void* list), "ppp", pad, parent, list);
WRAPPER(GstPadInstance, chainlistnotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, getrangefunc, int    , (void* pad, void* parent, uint64_t offset, uint32_t length, void* buffer), "ppUup", pad, parent, offset, length, buffer);
WRAPPER(GstPadInstance, getrangenotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, eventfunc, int    , (void* pad, void* parent, void* event), "ppp", pad, parent, event);
WRAPPER(GstPadInstance, eventnotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, queryfunc, int    , (void* pad, void* parent, void* query), "ppp", pad, parent, query);
WRAPPER(GstPadInstance, querynotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, iterintlinkfunc, void*  , (void* pad, void* parent), "pp", pad, parent);
WRAPPER(GstPadInstance, iterintlinknotify, void   , (void* a), "p", a);
WRAPPER(GstPadInstance, finalize_hook, void   , (void* hook_list, void* hook), "pp", hook_list, hook);
WRAPPER(GstPadInstance, eventfullfunc, int    , (void* pad, void* parent, void* event), "ppp", pad, parent, event);

#define SUPERGO()                       \
    GO(activatefunc, iFpp);             \
    GO(activatenotify, vFp);            \
    GO(activatemodefunc, iFppii);       \
    GO(activatemodenotify, vFp);        \
    GO(linkfunc, iFppp);                \
    GO(linknotify, vFp);                \
    GO(unlinkfunc, vFpp);               \
    GO(unlinknotify, vFp);              \
    GO(chainfunc, iFppp);               \
    GO(chainnotify, vFp);               \
    GO(chainlistfunc, iFppp);           \
    GO(chainlistnotify, vFp);           \
    GO(eventfunc, iFppp);               \
    GO(eventnotify, vFp);               \
    GO(queryfunc, iFppp);               \
    GO(querynotify, vFp);               \
    GO(iterintlinkfunc, pFpp);          \
    GO(iterintlinknotify, vFp);         \

static void unwrapGstObjectInstance(my_GstObjectInst_t* class)
{
    (void)class;
}
static void bridgeGstObjectInstance(my_GstObjectInst_t* class)
{
    (void)class;
}
static void unwrapGstElementInstance(my_GstElementInst_t* class)
{
    unwrapGstObjectInstance(&class->parent);
}
static void bridgeGstElementInstance(my_GstElementInst_t* class)
{
    bridgeGstObjectInstance(&class->parent);
}
static void unwrapGstBaseSrcInstance(my_GstBaseSrc_t* class)
{
    unwrapGstElementInstance(&class->parent);
}
static void bridgeGstBaseSrcInstance(my_GstBaseSrc_t* class)
{
    bridgeGstElementInstance(&class->parent);
}
static void unwrapGstPushSrcInstance(my_GstPushSrc_t* class)
{
    unwrapGstBaseSrcInstance(&class->parent);
}
static void bridgeGstPushSrcInstance(my_GstPushSrc_t* class)
{
    bridgeGstBaseSrcInstance(&class->parent);
}
static void unwrapGstBaseSinkInstance(my_GstBaseSink_t* class)
{
    unwrapGstElementInstance(&class->parent);
}
static void bridgeGstBaseSinkInstance(my_GstBaseSink_t* class)
{
    bridgeGstElementInstance(&class->parent);
}
static void unwrapGstPadInstance(my_GstPad_t* class)
{
    unwrapGstObjectInstance(&class->object);
    #define GO(A, W)   class->A = find_##A##_GstPadInstance (class->A)
    SUPERGO()
    #undef GO
    class->getrangefunc = find_getrangefunc_GstPadInstance (class->getrangefunc);
    class->getrangenotify = find_getrangenotify_GstPadInstance (class->getrangenotify);
    class->ABI.abi.eventfullfunc = find_eventfullfunc_GstPadInstance (class->ABI.abi.eventfullfunc);
    class->probes.finalize_hook = find_finalize_hook_GstPadInstance (class->probes.finalize_hook);
}
static void bridgeGstPadInstance(my_GstPad_t* class)
{
    bridgeGstObjectInstance(&class->object);
    #define GO(A, W) autobridge_##A##_GstPadInstance (W, class->A)
    SUPERGO()
    #undef GO
    autobridge_getrangenotify_GstPadInstance (vFp, class->getrangenotify);
    autobridge_eventfullfunc_GstPadInstance (iFppp, class->ABI.abi.eventfullfunc);
    autobridge_finalize_hook_GstPadInstance (vFpp, class->probes.finalize_hook);
}
#undef SUPERGO

"""

INSTANCE_DISPATCH = r"""
void unwrapGTKInstance(void* cl, int type)
{
    if(!cl) return;
    if(type==my_GstPad) unwrapGstPadInstance((my_GstPad_t*)cl);
    else if(type==my_GstPushSrc) unwrapGstPushSrcInstance((my_GstPushSrc_t*)cl);
    else if(type==my_GstBaseSrc) unwrapGstBaseSrcInstance((my_GstBaseSrc_t*)cl);
    else if(type==my_GstBaseSink) unwrapGstBaseSinkInstance((my_GstBaseSink_t*)cl);
    else if(type==my_GstElement) unwrapGstElementInstance((my_GstElementInst_t*)cl);
    else if(type==my_GstObject) unwrapGstObjectInstance((my_GstObjectInst_t*)cl);
}

void bridgeGTKInstance(void* cl, int type)
{
    if(!cl) return;
    if(type==my_GstPad) bridgeGstPadInstance((my_GstPad_t*)cl);
    else if(type==my_GstPushSrc) bridgeGstPushSrcInstance((my_GstPushSrc_t*)cl);
    else if(type==my_GstBaseSrc) bridgeGstBaseSrcInstance((my_GstBaseSrc_t*)cl);
    else if(type==my_GstBaseSink) bridgeGstBaseSinkInstance((my_GstBaseSink_t*)cl);
    else if(type==my_GstElement) bridgeGstElementInstance((my_GstElementInst_t*)cl);
    else if(type==my_GstObject) bridgeGstObjectInstance((my_GstObjectInst_t*)cl);
}

"""

GSTBASE_C = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define _GNU_SOURCE
#include <dlfcn.h>

#include "wrappedlibs.h"

#include "debug.h"
#include "wrapper.h"
#include "bridge.h"
#include "librarian/library_private.h"
#include "x86emu.h"
#include "gtkclass.h"

#ifdef ANDROID
    const char* gstbaseName = "libgstbase-1.0.so";
#else
    const char* gstbaseName = "libgstbase-1.0.so.0";
#endif

#define LIBNAME gstbase

typedef size_t  (*LFv_t)();

#define ADDED_FUNCTIONS()                   \
    GO(gst_base_src_get_type, LFv_t)        \
    GO(gst_push_src_get_type, LFv_t)        \
    GO(gst_base_sink_get_type, LFv_t)       \

#include "generated/wrappedgstbasetypes.h"
#include "wrappercallback.h"

#define PRE_INIT    \
    if(box86_nogtk) \
        return -1;

#define CUSTOM_INIT \
        getMy(lib); \
        SetGstBaseSrcID(my->gst_base_src_get_type()); \
        SetGstPushSrcID(my->gst_push_src_get_type()); \
        SetGstBaseSinkID(my->gst_base_sink_get_type());

#define CUSTOM_FINI \
    freeMy();

#include "wrappedlib_init.h"
'''


def must_replace(text: str, old: str, new: str, where: str) -> str:
    if old not in text:
        raise SystemExit(f"{where}: expected snippet not found:\n{old[:160]}")
    return text.replace(old, new, 1)


def patch_gtkclass_h(path: pathlib.Path) -> None:
    text = path.read_text()
    if MARKER in text:
        print(f"skip {path} (already patched)")
        return
    text = must_replace(
        text,
        "typedef my_GstURIHandlerInterface_t my_GstURIHandlerClass_t;\n",
        "typedef my_GstURIHandlerInterface_t my_GstURIHandlerClass_t;\n" + STRUCTS,
        str(path),
    )
    text2, n = re.subn(
        r"GTKCLASS\(GstURIHandler\)(\s*\\\n)",
        "GTKCLASS(GstURIHandler)\\1"
        "GTKCLASS(GstBaseSrc)\\1"
        "GTKCLASS(GstPushSrc)\\1"
        "GTKCLASS(GstBaseSink)\\1",
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit(f"{path}: GTKCLASS(GstURIHandler) not found")
    text = text2
    text = must_replace(
        text,
        "void* wrapCopyGTKClass(void* cl, int type);\nvoid* unwrapCopyGTKClass(void* klass, int type);\n",
        "void* wrapCopyGTKClass(void* cl, int type);\n"
        "void* unwrapCopyGTKClass(void* klass, int type);\n"
        "void unwrapGTKInstance(void* cl, int type);\n"
        "void bridgeGTKInstance(void* cl, int type);\n",
        str(path),
    )
    path.write_text(text)
    print(f"patched {path}")


def patch_gtkclass_c(path: pathlib.Path) -> None:
    text = path.read_text()
    if MARKER in text:
        print(f"skip {path} (already patched)")
        return
    needle = "// No more wrap/unwrap\n#undef WRAPPER"
    text = must_replace(text, needle, WRAP + needle, str(path))
    text = must_replace(
        text,
        "static int my_funcs_instance_init_##A(void* instance, void* data) {                             \\\n"
        "    printf_log(LOG_DEBUG, \"Calling fct_funcs_instance_init_\" #A \" wrapper\\n\");                  \\\n"
        "    return (int)RunFunctionFmt(fct_funcs_instance_init_##A, \"pp\", instance, data);  \\\n"
        "}",
        "static int my_funcs_instance_init_##A(void* instance, void* data) {                             \\\n"
        "    printf_log(LOG_DEBUG, \"Calling fct_funcs_instance_init_\" #A \" wrapper\\n\");                  \\\n"
        "    int ret = (int)RunFunctionFmt(fct_funcs_instance_init_##A, \"pp\", instance, data);  \\\n"
        "    unwrapGTKInstance(instance, fct_parent_##A);                                               \\\n"
        "    bridgeGTKInstance(instance, fct_parent_##A);                                               \\\n"
        "    return ret;                                                                                \\\n"
        "}",
        str(path),
    )
    text = must_replace(
        text,
        "static void wrapGTKClass(void* cl, int type)\n",
        INSTANCE_DISPATCH + "static void wrapGTKClass(void* cl, int type)\n",
        str(path),
    )
    path.write_text(text)
    print(f"patched {path}")


def patch_gstbase_c(path: pathlib.Path) -> None:
    text = path.read_text()
    if "SetGstBaseSrcID" in text:
        print(f"skip {path} (already patched)")
        return
    path.write_text(GSTBASE_C)
    print(f"rewrote {path}")


def patch_gstbase_private(path: pathlib.Path) -> None:
    text = path.read_text()
    if "GO(gst_base_src_get_type, pFv)" in text:
        print(f"skip {path} (already patched)")
        return
    reps = [
        ("//GO(gst_base_src_get_type, ", "GO(gst_base_src_get_type, pFv)"),
        ("//GO(gst_push_src_get_type, ", "GO(gst_push_src_get_type, pFv)"),
        ("//GO(gst_base_sink_get_type, ", "GO(gst_base_sink_get_type, pFv)"),
    ]
    lines = text.splitlines(True)
    out = []
    found = set()
    for line in lines:
        done = False
        for prefix, repl in reps:
            if line.startswith(prefix):
                out.append(repl + "\n")
                found.add(prefix)
                done = True
                break
        if not done:
            out.append(line)
    missing = [p for p, _ in reps if p not in found]
    if missing:
        raise SystemExit(f"{path}: missing {missing}")
    path.write_text("".join(out))
    print(f"patched {path}")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} /path/to/box86", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    patch_gtkclass_h(root / "src/include/gtkclass.h")
    patch_gtkclass_c(root / "src/tools/gtkclass.c")
    patch_gstbase_c(root / "src/wrapped/wrappedgstbase.c")
    patch_gstbase_private(root / "src/wrapped/wrappedgstbase_private.h")
    print("box86 gstreamer dataflow patch complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
