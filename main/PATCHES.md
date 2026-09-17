# Main_MiSTer changes for WinEXE

Do **not** fork more of Main than this. Custom binary name: `MiSTer_WinEXE`.
Activation is the supported per-core INI key, already parsed by upstream:

```
user_io.cpp / user_io_init()
  cfg_parse();
  const char *main = getFullPath(cfg.main);
  if (strcasecmp(main, getappname()) && FileExists(main))
      app_restart(path, xml, main);
```

`cfg.main` defaults to `"MiSTer"` (`cfg.cpp`). Append the `[WinEXE]` /
`[WinEXE_Test]` sections from `mister/WinEXE.ini` to `/media/fat/MiSTer.ini`
(Main does not load a standalone `WinEXE.ini`). That sets
`main=MiSTer_WinEXE`. `getFullPath()` resolves a bare filename under the
SD root (`/media/fat/MiSTer_WinEXE`).

After `app_restart()`, the FPGA core stays loaded; only the HPS process is
replaced. The custom binary is a **full** Main executable with a small
WinEXE hook, not a plugin.

## Files to add

| Path in Main_MiSTer | Source in this repo |
|---|---|
| `support/winexe/winexe.cpp` | `main/support/winexe/winexe.cpp` |
| `support/winexe/winexe.h` | declare `winexe_init`, `winexe_poll`, `is_winexe` |

Add `winexe.cpp` to the Main makefile object list the same way `support/x86` is linked.

## Files to touch (minimal)

### 1. `user_io.h` / `user_io.cpp` — `is_winexe()`

Mirror `is_x86()`:

```c
char is_winexe()
{
    const char *n = user_io_get_core_name(1); // orig CONF_STR name
    return !strcasecmp(n, "WinEXE") || !strcasecmp(n, "WinEXE_Test");
}
```

Accept `WinEXE_Test` so the hook can be exercised on the **current** RBF
before the first OSD Quartus build.

### 2. `user_io.cpp` — `user_io_init()` after `parse_config()`

```c
if (is_winexe()) winexe_init();
```

`winexe_init()` runs `ss1-winexe-launch.sh idle` so loading the core does
not start Wine.

### 3. `user_io.cpp` — `user_io_poll()` next to other core polls

Inside `if (core_type == CORE_TYPE_8BIT && !is_menu())`, after
`check_status_change()`:

```c
if (is_winexe()) winexe_poll();
```

Edge-detect is not used. MiSTer menu already pulses `user_io_status_set(opt, 1)` then `user_io_status_set(opt, 0)` in the same T/R handler (`menu.cpp`). Polling `cur_status` later never sees the 1.

Hook: at the end of `user_io_status_set()`, if `is_winexe() && value`, call `winexe_status_event(opt, value)`. That observes Restart/Stop. **Do not clear T bits** — menu already does.

At the start of `user_io_file_tx()`, if `is_winexe()`, call `winexe_wex_selected(name)` and **return** so the `.WEX` is never `user_io_set_download`'d into FPGA memory.

| Call | Meaning |
|---|---|
| `user_io_file_tx` while `is_winexe()` | `.WEX` selected → `ss1-winexe-launch.sh launch-wex <path>` (**not** streamed to FPGA) |
| start bit 5, value 1 | Restart current profile |
| start bit 6, value 1 | Stop / idle |

There is no numeric application index. `F0,WEX,Load Application...` is the picker.

Do **not** scrape `/tmp/OSD_VISIBLE`, the framebuffer, or the keyboard.

### 4. Input — **document only for Phase 1**

`input.cpp`:

- `static int grabbed = 1;`
- `ioctl(fd, EVIOCGRAB, (grabbed \|\| user_io_osd_is_visible()) ? 1 : 0);`
- `input_switch(-1)` on OSD open/close reapplies that formula (`user_io.cpp` ~3932)

Desired later behaviour:

| State | USB kbd/mouse | Pico IR / OSD combo pads |
|---|---|---|
| WinEXE, OSD closed | ungrabbed (Xorg) | stay grabbed (OSD still openable) |
| WinEXE, OSD open | grabbed (Main) | grabbed |
| other cores | unchanged | unchanged |

`input_switch(0)` is **not** that table: it ungrabs Pico too. Keep
`ss1-winexe-keep-input.sh` until Main grows a device-class filter around
the two `EVIOCGRAB` call sites (`input.cpp` ~5523 and `input_switch` ~6456).

## What not to change

- No new UIO opcode / mailbox
- No `user_io_file_tx` ROM loader for EXEs
- No per-app RBF
- Do not modify stock `MiSTer` on the SD card; ship a second binary

## Build (later, not this phase)

Cross-compile Main_MiSTer for ARMv7 as today. Install:

```
/media/fat/MiSTer_WinEXE
# plus [WinEXE] / [WinEXE_Test] sections in /media/fat/MiSTer.ini
```

The first **FPGA** rebuild is a separate, warned GHA Quartus job. Main
can be built without Quartus.
