# WMP / DirectShow / GStreamer / WaveOut status

**PARKED.** The parked player is genuine **Windows Media Player 7.1**.
This filename is historical. Do not continue WMP memory/audio
integration in the v0.1.0-beta release. WMP is **not** in the WinEXE OSD
list. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

Checkpoint date: 2026-09-17.

Windows Media Player 9 is fundamentally working through the WinEXE
stack. This document is the restart point when WMP is un-parked.

Do **not** start Command & Conquer from this work. Do **not** replace the
original global Box86. Do **not** implement `IReferenceClock` unless a
later run shows remaining crackle is clock/pacing rather than producer
stalls. Next WMP blocker is `wmplayer.exe` RAM growth, not WaveOut.

## Proven

* Genuine XP SP3 WMP9 **9.00.00.4503** launches on dummy Xorg + WinEXE_Test.
* Wine DirectShow graph construction works under `box86-gstflow`.
* Box86 GStreamer wrapping is sufficient for real native ARM GStreamer
  dataflow (private GStreamer 1.18.4 under `/media/fat/Windows/runtime/gstreamer`).
* PCM WAV playback works through Wine DirectShow.
* Physical audio has been heard on the SuperStation.
* Wine DirectSound works but crackles and drops samples.
* Custom SS1 DirectShow WaveOut renderer (`ss1waveout.ax`) works and is
  substantially better than DirectSound.

## Not yet done

* MP3 through the final WaveOut path (Winamp MP3 via `out_wave.dll` is
  already proven; WMP MP3 is not).
* WMP built-in visualisations through WaveOut.
* WMP memory-usage investigation.
* Integrating `ss1waveout.ax` into the actual WMP9 graph (current best
  audio was the harness, not WMP).
* WMP is parked; WinEXE OSD profiles are in [WINEXE_CORE.md](WINEXE_CORE.md).

## Box86 binaries (do not replace original)

Keep all three on the SuperStation. Only WMP / DirectShow / gst harness
sessions use the gstflow binary.

| Binary | Role |
|---|---|
| `/media/fat/Windows/box86-ss1/box86` | Original working Box86. **Untouched rollback.** Default Wine loader. |
| `/media/fat/Windows/box86-ss1/box86-gst` | Factory / plugin stage. |
| `/media/fat/Windows/box86-ss1/box86-gstflow` | Current working multimedia test binary. |

WMP launcher uses `scripts/ss1-winexe-wine-gstflow.sh` installed as
`/media/fat/Windows/bin/wine-gstflow`. That wrapper execs `box86-gstflow`
and does **not** overwrite `/media/fat/Windows/bin/wine`.

Patches (GitHub Actions, not compiled on the SuperStation):

* `scripts/patch-box86-gst.py` — GstTaskPool, GstElement, GstBin, GstPad,
  GstURIHandler, GstBufferPool, plus plugin accessors/wrappers as needed.
* `scripts/patch-box86-gst-dataflow.py` — GstBaseSrc, GstPushSrc,
  GstBaseSink, GstPad instance callback bridging.

Workflows: `.github/workflows/build-box86-gst.yml`,
`.github/workflows/build-box86-gstflow.yml`.

Standalone i386 GStreamer harness (`scripts/ss1-gst-harness.c`,
`scripts/ss1-gst-harness.sh`):

```
filesrc → wavparse → fakesink
```

now creates, links, enters PLAYING, streams PCM, reaches EOS, and exits
successfully. Workflow: `.github/workflows/build-gst-harness.yml`.

## WMP DirectShow result

Minimal Wine DirectShow graph under `box86-gstflow`:

```
Reader → GStreamer splitter → audio renderer
```

PCM WAV:

* `RenderFile` `S_OK`
* duration correct
* state Running
* playback position advances in real time
* `EC_COMPLETE` received

So the WMP / DirectShow / GStreamer pipeline is fundamentally working.
WMP UI works. Physical audio works.

## DirectSound finding

Wine 7.1 DirectShow does **not** contain a genuine WaveOut renderer.

Both:

* `CLSID_AudioRender`
* `CLSID_DSoundRender`

map to Wine's DirectSound renderer (`dsound_render_create`).

DirectSound produced sample drops, underruns, and audible crackling even
in the minimal DirectShow harness with **no WMP**. DirectSound instability
is therefore independent of WMP.

Do not pursue registry merits / CLSID selection as a WaveOut fix. Do not
load XP `quartz.dll`.

## Custom SS1 WaveOut DirectShow renderer

Preserve `ss1waveout.ax` (source: `scripts/ss1-winexe-waveout.c`,
`scripts/ss1-winexe-waveout.h`, `scripts/ss1waveout.def`).

Private CLSID `{B7E3C101-5A42-4D8F-9C1E-A1B2C3D4E5F6}`.

Loaded privately with `DllGetClassObject`:

* no `regsvr32`
* no DirectShow merit changes
* no XP quartz
* no global Wine changes

Audio path:

```
DirectShow → GStreamer splitter → SS1 WaveOut Renderer
  → WinMM waveOut* → winealsa → SuperStation audio
```

Same broad WaveOut backend already proven by Winamp `out_wave.dll`.

Phase 1 harness: `scripts/ss1-winexe-dshow.c` / `scripts/ss1-winexe-dshow.sh`.
`RenderFile` then disconnect/remove DSound, `AddFilter` SS1 WaveOut,
`ConnectDirect` splitter → renderer. Fail if DSound remains.

Build: `.github/workflows/build-dshow-harness.yml` (i686 MinGW,
`-static-libgcc -Wl,--kill-at`).

## Best-known audio configuration (2026-09-17)

Diagnostic only; not frozen as a product default, but it is the current
best-known WaveOut setup. Do not change it until WMP integration is
tested.

| Parameter | Value |
|---|---|
| WaveOut buffers | 12 |
| Buffer length | 30 ms |
| Total capacity | ~360 ms |
| Prime before `waveOutRestart` | 9 buffers |
| Input | 44.1 kHz / 16-bit / stereo PCM |
| DirectSound | not used |
| WMP | not used (harness) |
| Presenter | not used (audio-only) |

Physical result: **seemed really good**.

30-second PCM integrity:

| Metric | Value |
|---|---|
| received | 5,292,000 |
| submitted | 5,292,000 |
| completed | 5,292,000 |
| dropped | 0 |
| exact match | YES |
| Receive count | 646 |
| WaveOut writes | 1292 |
| `WOM_DONE` | 1292 |
| STARVE | 0 |
| WRITE_ABORT | none |
| `EC_COMPLETE` | `S_OK` |

Large DirectShow samples were split across WaveOut buffers with no lost
remainder.

## Cadence finding

One genuine producer stall:

* ~1095 ms `IMemInputPin::Receive` gap
* around t ≈ 15.3 s
* `in_flight` was still 11 when Receive resumed (12×30 ms queue)

Other ~45–65 ms gaps were normal backpressure because the WaveOut queue
was full.

This explains the earlier 8 × 20 ms (~160 ms) configuration occasionally
degrading into “Morse code” audio: the queue was too shallow to absorb a
~1.1 s upstream GStreamer / DirectShow scheduling stall.

Current interpretation:

**Remaining crackle/stutter source is upstream producer/scheduling
stalls, not WaveOut dropping data, and not DirectSound.**

Do not implement `IReferenceClock` yet.

## WMP on the SuperStation

Genuine XP files stay on the device only. Staging tree:
`/media/fat/Windows/apps/wmp9`. Installer copies them into the prefix
(`Program Files\Windows Media Player` + selected `system32` natives) and
does **not** overwrite Wine `quartz.dll` / `msdmo.dll` / `qasf.dll`.

| Script | Role |
|---|---|
| `scripts/ss1-winexe-wmp9-install.sh` | Copy + `regsvr32` from staged XP files |
| `scripts/ss1-winexe-wmp9-config.sh` | First-run / native DLL overrides (wineserver stopped) |
| `scripts/ss1-winexe-wmp9.reg` | Path / EULA / no-auto-upgrade keys |
| `scripts/ss1-winexe-wmp9.sh` | Launch `wmplayer.exe` via `wine-gstflow` |
| `scripts/ss1-winexe-wine-gstflow.sh` | Box86 gstflow Wine loader |
| `scripts/ss1-winexe-gst-env.sh` | Private ARMHF GStreamer env |
| `scripts/ss1-winexe-prefix-backup.sh` | Snapshot the ext4 prefix image |
| `scripts/ss1-winexe-cocreate.c` | Tiny CoCreate COM diagnostic |

WMP sessions disable Gecko (`mshtml` / `ieframe` / `shdocvw`).

## Next session

1. Integrate the proven custom WaveOut renderer into WMP9.
2. Test PCM WAV through actual WMP.
3. Test MP3.
4. Test WMP built-in visualisations.
5. Investigate WMP memory usage.
6. Checkpoint.
7. Begin turning WinEXE into a proper MiSTer core with OSD-selectable
   application profiles.

Do not start C&C.
