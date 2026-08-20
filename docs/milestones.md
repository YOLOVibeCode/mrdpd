# Milestones (implementation plan in-repo)

Rolling-wave: only [tasks/m0.md](tasks/m0.md) and [tasks/m1.md](tasks/m1.md) are fully tasked. Later milestones are gates, not a Gantt chart.

Survival gate: **M6**. No T2 feature work until M6 is interop-green on iPad, unless it unblocks a T1 defect.

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
| 7 | Clipboard | **new** ClipboardBridge on first test | Text round-trip; then images/files |
| 8 | Resize | Resize callback + SCK reconfigure | iPad rotation |
| 9 | Multimon | Per-display streams + virtual desktop math | C-DESK two monitors; depends R1 |
| 10 | EGFX | **new** AvcFrameSink on first test | A/B vs RemoteFX; fallback allowed |
| 11 | Audio | **new** AudioSource on first test | Tone round-trip |
| 12 | Daemon | Launch Agent, codesign, TCC UX | Clean VM install |

## Rhythm (every M)

1. Failing test citing spec ID (ISP: extract protocol only if needed).
2. Stub green.
3. Real implementation, same suite green.
4. E2E if user-visible.
5. Interop log in the task file.
6. Update [traceability.md](traceability.md) and [dod.md](dod.md).
