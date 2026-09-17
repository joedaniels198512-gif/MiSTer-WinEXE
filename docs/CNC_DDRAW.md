# C&C Gold DirectDraw diagnostic (Wine 7.1 / WinEXE)

Stock `C&C95.EXE` is not in git. SuperStation copy MD5
`aae55c89aa7927e5c0d4519ef9684a01` (unchanged on disk). Official Westwood XP
`THIPX32.DLL` only. `CONQUER.INI`: `Resolution=1`, `VideoBackBuffer=1`,
`HardwareFills=0`. No cnc-ddraw, no PAL8, no FPGA video change, no EXE patch.

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

Next observed boundary (not a no-CD patch):

`Please insert a Command & Conquer CD into the CD-ROM drive.`

ISO helper already mounts `NOD95` with root `MOVIES.MIX` as Wine `D:`.
CD presentation is a separate diagnostic.

## Later architecture (not started)

If more old-VRAM `GetCaps` checks appear, keep counting them with the
same in-memory instrument. Do not patch the EXE. Candidates after a
full playthrough:

- A: small generic DirectDraw GetCaps compatibility shim (profile)
- B: PAL8 / shared-DDR video-memory backend
- C: both

`ss1-cnc-ddraw.exe` / `ss1-cnc-focus.exe` / `ss1-cnc-capslie.exe` are
rebuildable PE32 probes. Do not ship copyrighted C&C files.
