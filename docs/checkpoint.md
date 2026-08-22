# Checkpoint — 2026-08-21 (after M6 iPad smoke)

Read this first in a new session, then [AGENTS.md](../AGENTS.md), [method.md](method.md), [spec.md](spec.md), [traceability.md](traceability.md).

**M6 is the survival gate.** Do not start T2 (multimon, EGFX, audio, file clipboard) until iPad is `interop-green`, unless a T2 item unblocks a T1 bug. **M8 resize is T1** (`T1-MON-01`) and is the next user-visible fix for “huge desktop / not smooth.” Do not write `docs/tasks/m7.md`+ until the previous gate is honestly green or explicitly unblocked.

## Where we are

The Mac can serve the **logged-in console** over RDP (RemoteFX, ABI v1). Windows App on iPad **saw the desktop and could type some keys**. It was **not smooth**. Session size is locked to the first `SCDisplay` (lab: **3360×1890**). Clicks/Cmd/scroll were not fully scored. Changing iPad resolution does **not** yet resize the stream (M8) and must **not** change the Mac’s hardware display mode without an ADR.

| M | Name | Status |
| --- | --- | --- |
| 0 | Docs + ISP slice (StubEngine, FrameSource, InputSink, EngineKit) | done |
| 1 | Real IronRDP engine, headless #FF00FF BMP, spikes R1/R2/R5 | done |
| 2 | 1080p quadrant pattern, FreeRDP GDI BGRA32 | done (iPad **pattern** never run; live desktop later covered M5) |
| 3 | US keymap + FastPath → `RecordingInputSink` | done (no CGEvent) |
| 4 | `SCKFrameSource` + dirty rects, TCC-free vs `just test-local` | done |
| 5 | Live view: pacer, cursor composite, `mrdpd-serve` | done; iPad **view** 2026-08-21 |
| 6 | Inject: `DisplayMap` + `CGEventInputSink` | **partial**; iPad typing some; smoothness open |
| 7 | Clipboard | not started (T1; wait on M6 honesty / rolling-wave) |
| 8 | RDPEDISP + SCK reconfigure (iPad size / rotate) | **next for smoothness/fit** |
| 9–12 | Multimon, EGFX, audio, daemon | after M6 interop-green (T2 items) |

## What exists in tree

- **C ABI v1** (`docs/abi.md` → `include/mrdpd_engine.h`): start/stop/`push_frame`/input callbacks. No clipboard, audio, AVC, layout.
- **StubEngine** + **mrdpd-engine** (`ironrdp-server` **0.13.0** crates.io, `helper`+`rayon`, QoiZ compile-out). Pin is **not** git master. `RdpServer::run()` is `!Send` → dedicated OS thread + current-thread Tokio.
- **FrameKit:** `Frame` / `FrameSource.nextFrame()` only / `SyntheticFrameSource` / `SCKFrameSource` / `DirtyRects` / `CaptureFrame` / `FramePacer` (60 fps cap).
- **InputKit:** `InputSink.handle` only / `RecordingInputSink` / `UsKeymap` / `DisplayMap` / `InjectionPlan` / `CGEventInputSink`.
- **EngineKit:** `dlopen` wrapper, `FramePump`, `BindHost` (refuse `0.0.0.0`/`::`/`*`), `ServeArgs` (strip SwiftPM `--`).
- **Lab bins:** `mrdpd-pattern` (1080p quadrants), `mrdpd-serve` (SCK → pacer → real engine → HID).
- **NLA (lab):** user `mrdpd`, password `changeme` (gitleaks-allowlisted; not the Mac login).

## How to run

TCC: Screen Recording **and** Accessibility on the **same** Terminal/Cursor that launches serve (`docs/tcc.md`). CI never grants. `just test` stays TCC-free.

```bash
just test                          # ABI + engine E2E + Swift; no TCC
just test-local                    # SCK + CGEvent HID mouse
just bench                         # T1-PERF-01 pacer only
just serve                         # 127.0.0.1:3390
just serve host=<tailscale-ip>     # iPad; never 0.0.0.0
just serve-pattern                 # 1080p quadrants (M2)
just test-freerdp                  # ignored sdl-freerdp GDI
just test-inject                   # FastPath mouse vs a running serve
```

If `just` is missing from PATH, use the recipes in `justfile` via `cargo` / `swift` directly.

iPad: Windows App → PC `100.x.x.x:3390` (or current `tailscale ip -4`), user `mrdpd` / `changeme`, accept ephemeral cert. One client at a time (T1-SEC-03).

## Interop (2026-08-21)

- **C-HEADLESS:** solid magenta + 1080p quadrants (RemoteFX, interior ±24).
- **C-FREERDP 3.30:** pattern GDI `PIXEL_FORMAT_BGRA32`; live serve GDI same.
- **C-IPAD:** desktop **rendered** at 3360×1890 over Tailscale; **some typing**; **not smooth**. Resize/Mac mode change not implemented. Click/drag/scroll/Cmd not fully scored. Log: `docs/tasks/m6.md`.

## Pitfalls (do not relearn)

- crates.io `ironrdp-server` 0.13.0 ≠ git master.
- Probe bind **without** `SO_REUSEADDR`, then IronRDP; wait on `GetLocalAddr`. Do not TCP-connect to wait (steals accept).
- Ready-line matching is case-sensitive `"listening"`.
- Kill leftover `mrdpd-serve` / `sdl-freerdp` before reconnect (one client).
- FreeRDP INFO needs a PTY (`script -q`) or GDI lines never appear.
- Stub cdylib may omit new `#[no_mangle]` until `cargo clean -p mrdpd-stub-engine`.
- Swift 6: no `NSLock` from async; SCK state is a serial `DispatchQueue`.
- `swift run mrdpd-serve -- host port` — `--` must be stripped (`ServeArgs`).
- Capture is **first display only**. Multi-monitor Mac: iPad may not see the display you care about until M9.
- Changing iPad resolution must **reconfigure SCK / RDP framebuffer** (M8), not `CGDisplaySetDisplayMode`, unless we write an ADR.

## Next (priority)

1. Confirm remaining M6 iPad input (click, drag, scroll, Cmd) even if laggy — then decide if M6 is “daily usable” enough to call the gate.
2. **M8** `T1-MON-01`: RDPEDISP + SCK reconfigure to iPad size. Expected to help fit **and** smoothness (fewer RemoteFX pixels). Does not retune the Mac panel.
3. Smoothness after that: LAN vs Tailscale notes; **M10** H.264/EGFX is T2 and waits on the M6 gate unless we explicitly unblock it.
4. M7 clipboard only after rolling-wave allows it (T1, but new protocol — first failing test creates `ClipboardBridge`).

## Tests that must stay true

- `just test` green, TCC-free.
- No new ABI methods “for later.”
- `FrameSource` still only `nextFrame()`. `InputSink` still only `handle(_:)`.
- No `ClipboardBridge` / `AudioSource` / `AvcFrameSink` until their first failing test.
