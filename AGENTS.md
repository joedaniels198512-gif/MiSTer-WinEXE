# Working on WinEXE

These rules apply throughout this repository. Keep technical detail in the existing documentation; this file defines how to work.

## Approach and scope

- Inspect Git status, the existing implementation, relevant profiles, scripts, and documentation before changing anything. Preserve unrelated user changes and ignored local artifacts.
- Prefer the smallest change that proves or fixes something. Reproduce and instrument failures before proposing speculative fixes.
- Do not redesign known-good subsystems without evidence. Preserve working Wine, Box86, Xorg, presenter, input, and audio behavior unless the task specifically requires changing it.
- Ask the user before making an architectural or scope-changing decision. Investigate ordinary build/test failures autonomously; a failed command alone does not require another permission request.
- Keep commits and checkpoints small enough to revert individual experiments. Separate experiments from unrelated cleanup.
- Treat historical documentation as context, not proof of current behavior. Resolve discrepancies against source and recorded evidence, and update affected documentation when behavior changes.

## Implementation boundaries

- Prefer application-specific fixes in profiles and helpers. Keep one shared FPGA core and the Main patch minimal; do not rebuild or modify FPGA logic for an application-only change without a demonstrated need.
- Preserve the warm Wine desktop lifecycle: app Stop returns to READY; full shutdown is separate. Check app switching, helper cleanup, presenter settings, CPU affinity, and memory recovery when changing lifecycle code.
- Preserve the framebuffer address/format contract across ARM, guest hooks, and RTL. Check PAL8-to-BGRX recovery after changes touching either path. The legacy `/dev/fb0` presenter is not the active WinEXE display path.
- Treat input ownership and OSD open/close behavior as regression-sensitive. Device numbering is currently assumed; do not silently broaden input grabs or change the handoff.
- Use `/media/fat/games/WinEXE` for current runtime work. Inspect old `/media/fat/Windows` references before reusing scripts; root overrides do not guarantee every path is relocatable.
- Preserve the known-good Box86 and Wine prefix. Keep experimental runtime variants alongside the baseline. WMP work remains parked unless explicitly requested.
- Do not commit or package user-supplied Windows/game binaries, media, disc images, saves, or device dumps. Distinguish project-built compatibility helpers from proprietary payloads.

## Build and validation

- Keep the repository buildable. Use the relevant component workflow as the build recipe; preserve ARMv7/Cortex-A9 and target glibc compatibility. Do not compile on the SuperStation.
- Production FPGA/Quartus builds must never run locally on this Mac, including through Rosetta or Docker: that route is too slow and unreliable. Use local source changes → authorized commit/push → GitHub Actions Quartus 17.0.2 build → retrieve and verify the generated artifact → controlled SuperStation One deployment → physical verification by the user. A request to edit or validate does not authorize committing, pushing, or deploying.
- Run relevant local validation after changes: source inspection, syntax/static checks, packaging tests, shell/Python validation, and lightweight compilation where practical. Report checks not run and why; production FPGA builds belong in CI only.
- Account for Linux case sensitivity even when local checks pass on macOS. A passing release/layout check does not establish package completeness or successful installation.
- For release changes, verify required runtime/helper artifacts and their provenance, fresh installation, and preservation of existing installations. Do not assume ignored local artifacts exist in CI or match current source.
- Keep tests focused on changed behavior and plausible regressions. Preserve useful instrumentation and record the component versions, settings, and evidence needed to reproduce results.

## Device access and evidence

- When device access is available, prefer inspect → change → build → deploy → test → collect evidence. Establish the actual device paths, installed versions, running core, and baseline before deployment.
- Never make destructive device changes, overwrite user data, force-push, or change system-level SS1 configuration without approval. Preserve stock MiSTer, user applications, saves, media, and prefixes; establish rollback before replacing runtime components.
- Do not claim that something works on SuperStation hardware unless the user has physically verified it. Attribute historical verification explicitly and do not extend it to a new build.
- Process success, framebuffer state, screenshots/dumps, and logs are not equivalent to the user's visible HDMI/CRT or audible audio verification. Report software observations and physical verification separately.
- For affected paths, exercise cold boot, warm launch/switch/restart/stop, repeated OSD input recovery, and core-exit cleanup. Include memory, cursor/first-frame, palette, and audio checks when relevant.
- Report what changed, what was tested, the evidence, remaining uncertainty, and the exact physical check still needed from the user.
