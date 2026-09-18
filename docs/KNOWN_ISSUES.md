# Known issues — WinEXE v0.1.0-beta

Honest limitations. Do not treat parked work as finished.

## Hardware / memory

- SuperStation / MiSTer HPS RAM is about **512 MB**. Large Windows
  processes can exhaust it.
- The launcher refuses a new app if `MemAvailable` is below
  `SS1_LAUNCH_MEM_FLOOR_KB` (default **48000**). This is intentional.
- Previous Wine apps are stopped before a new launch. Warm READY
  services (Xorg, presenter, input watcher) stay up.

## Input

- USB mouse/keyboard recovery assumes **event0 = mouse** and
  **event1 = keyboard** (`SS1_MOUSE_EVENT` / `SS1_KBD_EVENT`).
  Generic USB enumeration is **not** solved.
- A mouse-speed OSD control is **not implemented**.

## HDMI / presenter

- The first HDMI frame after presenter start is always force-copied
  to FPGA DDR. Later frames use skip-unchanged. Cursor motion uses a
  small rectangle write instead of a 1.2 MB full-frame copy.
- Some applications and load conditions still miss a 16.67 ms budget.
  Locked 60 fps is **not** claimed. Performance polish is future work.

## Application compatibility

| Status | Application | Notes |
|---|---|---|
| Working | Notepad, Paint | XP SP3 PE32 |
| Working | Minesweeper, Solitaire, FreeCell | XP games + `cards.dll` as documented |
| Minor fix | Hearts | Plays; **Pass Left** with the physical mouse is unreliable |
| Working | SimCity 2000 | Win95 `C:\SC2K\` tree |
| Working | Civilization II MGE | Gameplay and CD music confirmed on HDMI. **High Council / advisor video is unfinished.** Do not claim full multimedia. |
| Playable | Command & Conquer Gold | PAL8 path and palette verified; gameplay works; **performance remains an optimisation target** |
| Tested | Winamp 2.91 | Application / UI / playback-state testing. Do not treat every audio path as finished. |
| Parked | Windows Media Player 7.1 | Genuine UI works. Playback is parked (memory / compatibility). |

## Not in this beta

- Broken Sword and other unlisted titles
- Mouse-speed OSD
- Generic USB device mapping
- WMP playback
- Civ II advisor / High Council video
- Further C&C performance work

## Legal

Users must supply application files they are allowed to use.
This project does not ship those binaries.
