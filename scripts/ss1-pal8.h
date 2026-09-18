/*
 * WinEXE Direct PAL8 prototype — shared address map.
 *
 * Physical DDR (outside Linux 511 MB). FPGA ascal + pal8_fbctl read these.
 * ARM/Box86 mmap /dev/mem at the same VAs (identity) so the guest hook
 * can write pixels/palette with ordinary stores.
 *
 * Do not collide with:
 *   0x30000000  BGRX32 framebuffer A (1 228 800 bytes, stride 2560)
 *   0x30200000  this PAL8 allocation
 *   0x30400000  existing 4 KB mailbox
 */
#ifndef SS1_PAL8_ADDR_H
#define SS1_PAL8_ADDR_H

#define SS1_BGRX_PHYS          0x30000000UL
#define SS1_BGRX_STRIDE        2560
#define SS1_BGRX_SIZE          (640u * 480u * 4u)

#define SS1_PAL8_PHYS          0x30200000UL
#define SS1_PAL8_W             640
#define SS1_PAL8_H             480
#define SS1_PAL8_STRIDE        640
#define SS1_PAL8_SIZE          (640u * 480u)          /* 307 200 = 0x4B000 */

#define SS1_PAL8_PAL_PHYS      0x3024B000UL           /* 256 × uint32 00RRGGBB */
#define SS1_PAL8_PAL_ENTRIES   256
#define SS1_PAL8_PAL_SIZE      (256u * 4u)            /* 1024 */

#define SS1_PAL8_STATS_PHYS    0x3024C000UL           /* ARM/guest counters */
#define SS1_PAL8_STATS_SIZE    4096u

#define SS1_PAL8_ALLOC_END     0x303FFFFFUL           /* pad; mailbox follows */

#define SS1_MBOX_PHYS          0x30400000UL
#define SS1_MBOX_SIZE          4096u

#define SS1_PAL8_MAGIC         0x50384C38u            /* 'P8L8' */
#define SS1_PAL8_FLAG_EN       (1u << 0)

#define SS1_PAL8_ACTIVE_PATH   "/tmp/ss1-pal8.active"
#define SS1_PAL8_STATS_PATH    "/tmp/ss1-pal8.stats"
#define SS1_PAL8_MAP_LOG       "/tmp/ss1-pal8-map.log"

/* Mailbox words at SS1_MBOX_PHYS (FPGA reads 16 bytes / VBlank). */
#define SS1_MBOX_OFF_MAGIC     0
#define SS1_MBOX_OFF_FLAGS     4
#define SS1_MBOX_OFF_PAL_GEN   8
#define SS1_MBOX_OFF_PRESENTS  12

/* Stats page (not read by FPGA). */
#define SS1_STAT_PRESENTS      0
#define SS1_STAT_COPIES        4
#define SS1_STAT_COPY_NS_SUM   8    /* uint64 */
#define SS1_STAT_COPY_NS_MAX   16
#define SS1_STAT_BYTES         20   /* uint64 */
#define SS1_STAT_RING_I        28
#define SS1_STAT_RING          32   /* 64 × uint32 copy_ns */
#define SS1_STAT_RING_N        64

#endif /* SS1_PAL8_ADDR_H */
