# WinEXE v0.1.0-beta

WinEXE is a shared MiSTer / SuperStation Windows application
environment: Wine 7.1 + Box86 on ARMv7, dummy 640×480 Xorg, and
FPGA-backed HDMI (BGRX presenter, optional PAL8 for C&C).

This release is a packaging and documentation baseline for the
architecture that already runs on SuperStation. It does not add
applications or change Wine, Box86, or FPGA behaviour.

## Demonstrated applications (not shipped)

You must provide legally obtained files.

- Notepad, Paint
- Minesweeper, Solitaire, FreeCell
- Hearts (Pass Left remains problematic)
- SimCity 2000
- Civilization II MGE gameplay and music
- Winamp 2.91 application / UI / playback-state testing
- Command & Conquer Gold (PAL8 + gameplay; performance still in progress)

## Beta limitations

- ~512 MB HPS RAM; launches refuse below 48000 kB `MemAvailable`
- Compatibility varies by title
- C&C performance needs more work
- Hearts Pass Left
- WMP 7.1 playback is parked
- Civ II High Council / advisor video is unfinished
- Audio and presenter timing are still being refined
- USB input uses hardcoded event0/event1 defaults
- Mouse-speed OSD is not implemented
- Some loads still miss a 16.67 ms frame budget

## Legal

No Microsoft, Winamp, or game binaries are in the source tree or the
public zip. See `THIRD_PARTY_NOTICES.md`.
