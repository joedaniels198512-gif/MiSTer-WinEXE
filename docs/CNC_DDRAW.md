# C&C Gold DirectDraw diagnostic (Wine 7.1 / WinEXE)

Developer notes. C&C binaries and ISOs are not in git.

Stock `C&C95.EXE` is not in git. SuperStation copy MD5
`aae55c89aa7927e5c0d4519ef9684a01` (unchanged on disk). Official Westwood XP
`THIPX32.DLL` only. `CONQUER.INI`: `Resolution=1`, `VideoBackBuffer=1`,
`HardwareFills=0`. No cnc-ddraw, no on-disk EXE patch. Direct PAL8 present
is an optional prototype (`SS1_PAL8=1`): cached 640×480×8 → one 307 200-byte
copy to `0x30200000` + palette at `0x3024B000`. See `scripts/ss1-pal8.h`.

## What Wine actually provides

8-bit DirectDraw primary is usable:

- `SetDisplayMode(640,480,8)`, `PALETTEINDEXED8`
- `Lock` = `DD_OK`, `lpSurface` valid, pitch **640**
- `SetPalette` / `Blt` / `BltFast` = `DD_OK`

Wine primary `GetCaps` = **`0x00008A00`**:

`DDSCAPS_PRIMARYSURFACE | DDSCAPS_SYSTEMMEMORY | DDSCAPS_VISIBLE`

No `DDSCAPS_VIDEOMEMORY` (`0x4000`). Explicit
`CreateSurface(OFFSCREENPLAIN|VIDEOMEMORY)` returns `0x88760233`
(`DDERR_NODIRECTDRAWHW`) in this no-OpenGL prefix. `GetAvailableVidMem`
still prints a large number; that does not create a VIDEOMEMORY surface.

## Retail GetCaps tests (stock bytes)

Module base `0x400000`.

| Site | VA | RVA | Bytes | Meaning |
|---|---|---|---|---|
| Primary | `0x4A9C5D` | **`0xA9C5D`** | `F6 45 57 08 0F 84 9C 00 00 00` | `test [ebp+57h],08h` (`DDSCAPS_SYSTEMMEMORY`); **JE success**. Else ODS `C&C95 - Unable to allocate primary surface.` + MessageBox id `0x2DE` |
| Back buffer | `0x4A9DAA` | **`0xA9DAA`** | `F6 45 57 08 74 39` | Same bit. JE keep-as-video; fallthrough release/recreate sysmem |
| Icon cache | `0x4C9507` | `0xC9507` | `F6 44 24 01 08 74 1b` | Same bit. Else `Release`+NULL+`return 0` (`Cache_It` concept). Not reached before the CD dialog |

Primary caller: `mov eax,[0x00541AEC]` (CreateSurface out-ptr),
`call [edx+38h]` (`IDirectDrawSurface::GetCaps`). Tests **SYSTEMMEMORY
only**, not VIDEOMEMORY.

## In-memory caps substitution (diagnostic only)

`scripts/ss1-cnc-capslie.c` plants a cave after GetCaps:

```
and dword [ebp+56h], ~0x00000800   ; clear SYSTEMMEMORY
or  dword [ebp+56h],  0x00004000   ; set VIDEOMEMORY
```

Does not write `C&C95.EXE`. After this lie:

- primary warning gone
- 640×480 `OFFSCREENPLAIN` back buffer created and attached
- `SetPalette` + `SetEntries(0,256)` succeed
- primary `Lock`/`Unlock` (`DDLOCK_WAIT`) repeats; pitch 640
- C&C draws its own paletted UI (green-on-black CD insert dialog)
- no Win32 104×107 warning MessageBox

Wine Lock dumps still show real caps `0x8A00`. Only C&C’s local `dwCaps`
was lied to.

## CD presentation (Wine D:)

Linux loop-mount of `CnC_NOD95.iso` plus `dosdevices/d:` → mount and
`d::` → `/dev/loopN` is **not** enough. Win32 then reported:

| API | Result |
|---|---|
| `GetDriveType(D:)` | `DRIVE_CDROM` (5) — C&C does enumerate D: |
| `GetVolumeInformation(D:)` | **FAIL** `ERROR_INVALID_FUNCTION` (1), empty label |
| `CreateFile(D:\movies.mix)` | OK |

C&C imports `GetDriveTypeA`, `GetVolumeInformationA`, `CreateFileA`.
It only treats a drive as a C&C CD when the type is CD-ROM **and** the
label is `GDI95` / `NOD95` / `COVERT` **and** `MOVIES.MIX` opens.

Wine 7.1 `GetVolumeInformation` uses mountmgr
(`FileFsVolumeInformation` → `STATUS_NOT_IMPLEMENTED` if QUERY fails).
`ss1-winexe-cnc-cd.sh` now calls `ss1-cnc-cdprobe.exe --set-cdrom`
(`IOCTL_MOUNTMGR_DEFINE_UNIX_DRIVE`, same as winecfg). After that:

`GetDriveType=5`, `label=NOD95`, `fs=CDFS`, `MOVIES.MIX` readable.

C&C’s own log: `GetDriveTypeW c:\\ → 3`, `d:\\ → 5`, `z:\\ → 3`, then
`GetVolumeInformationByHandleW`. The insert-CD dialog disappeared.

**Next boundary (do not fix here):** privileged instruction at
`C&C95` VA `0x004DD5B4` / RVA `0xDD5B4`:

`mov edx, 0x3DA` / `in al, dx` / `test al, 08h` — VGA status / VBlank
poll. Wine Application Error dialog. No EXE patch. Icon-cache
`SYSTEMMEMORY` test at `0xC9507` was not reached.

## Direct PAL8 prototype (not a generic ddraw backend)

Runtime-only: `ss1-pal8-map.so` identity-maps FPGA DDR; `ss1-cnc-pal8.dll`
hooks `ddraw_surface_update_frontbuffer` and skips GDI/X for the qualifying
fullscreen P8 primary. Mailbox `0x30400000` bit0 selects PAL8 vs BGRX.
Stop/cleanup clears the flag so Explorer stays on the working BGRX path.

`ss1-cnc-ddraw.exe` / `ss1-cnc-focus.exe` / `ss1-cnc-capslie.exe` are
rebuildable PE32 probes. Do not ship copyrighted C&C files.
