# Milestones (implementation plan in-repo)

Rolling-wave: [tasks/m1.md](tasks/m1.md)–[tasks/m6.md](tasks/m6.md) are tasked (`m2`/`m5`/`m6` iPad deferred). Later milestones are gates, not a Gantt chart.

Survival gate: **M6**. No T2 feature work until M6 is interop-green on iPad, unless it unblocks a T1 defect.

**Priority after M6 (2026-10-04): the viewport track V0–V5** below ([ADR 0006](adr/0006-viewports.md)–[0009](adr/0009-reuse-not-fork.md)). It replaces M8–M10 and runs before M7, M11, and M12.

| M | Name | Constituents proven before wiring | Gate |
| --- | --- | --- | --- |
| 0a | Docs pack | — | This folder exists; IDs 1:1 with traceability |
| 0b | ISP slice | Frame, InputEvent, ABI v1, StubEngine, FrameSource, InputSink, EngineKit | `just test` green; no IronRDP |
| 1 | Real engine | StubEngine suite on real dylib | Headless BMP solid color; spikes R1 R2 R5 written |
| 2 | Pattern | SyntheticFrameSource 1080p | Golden + iPad/FreeRDP show pattern |
| 3 | Input decode | Keymap tables + ABI callbacks | Sequence lands in RecordingInputSink |
| 4 | Capture | SCKFrameSource vs FrameSource contract | Local TCC; dirty rects |
| 5 | Live view | M4 + M1 | Live desktop LAN; bench T1-PERF-01/03/04 |
| 6 | Inject | CGEventInputSink vs InputSink contract | iPad types and clicks — **daily usable** |
| 7 | Clipboard | **new** ClipboardBridge on first test | Text round-trip; then images/files. **After V3** |
| 8 | Resize | **Folded into V1** (T1-MON-01 is part of T1-VP-02) | — |
| 9 | Multimon | **Folded into V3** for viewports; desktop GCC multimon (T2-MON-01…03) stays T2 after V4, depends R1 | C-DESK two monitors |
| 10 | EGFX | **Folded into V4** (T1-GFX-07, ADR 0007) | — |
| 11 | Audio | **new** AudioSource on first test | Tone round-trip |
| 12 | Daemon | Launch Agent, codesign, TCC UX | Clean VM install |

## Viewport track (V0–V5)

Each V gate has an automated part (`just live-check` grows a test per ID) and a device part (iPad interop log in `docs/tasks/vN.md`).

| V | Name | IDs | Gate |
| --- | --- | --- | --- |
| V0 | Probe | M6 device scoring; capability log | One iPad session answers [tasks/v0.md](tasks/v0.md): M6 input scored; Windows App facts (two windows, size requested, Cmd mapping, hotkey passthrough, EGFX caps) recorded |
| V1 | Any display, client-sized | T1-VP-01, T1-VP-02 (incl. T1-MON-01) | iPad full-screen and a 4K window each show a chosen Mac display at their own resolution, crisp, input exact through the bars |
| V2 | Navigate | T1-VP-03, T1-VP-04 | From the iPad: hotkey switch < 300 ms to first new frame; HUD; overview pick by tap |
| V3 | Two screens at once | T1-VP-05, T1-VP-06, ABI v2 | Two concurrent viewports (two clients or two windows) show different displays and switch independently; cursor never fights |
| V4 | Smooth at 4K | T1-GFX-06, T1-GFX-07, T1-GFX-08, T1-PERF-05 | Client-side cursor; H.264 on Windows App; two-viewport budget met on the owner's Mac |
| V5 | Native iPad client | T2-NAT-01…06 | **Only if [ADR 0008](adr/0008-native-ipad-client.md) is accepted.** iPad screen and 4K as two windows of one app, picker strip, Mac-correct keys, precise scrolling |

## Rhythm (every M)

1. Failing test citing spec ID (ISP: extract protocol only if needed).
2. Stub green.
3. Real implementation, same suite green.
4. E2E if user-visible.
5. Interop log in the task file.
6. Update [traceability.md](traceability.md) and [dod.md](dod.md).
