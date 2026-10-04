# Checkpoint — 2026-08-21 (after M6 iPad smoke)

Read this first in a new session, then [AGENTS.md](../AGENTS.md), [method.md](method.md), [spec.md](spec.md), [traceability.md](traceability.md).

**M6 is the survival gate.** Do not start T2 (multimon, EGFX, audio, file clipboard) until iPad is `interop-green`, unless a T2 item unblocks a T1 bug.

**Update 2026-10-04 — architecture pass.** The owner's target is a Mac with three displays driven from an iPad Pro plus an external 4K, each client screen an independent, switchable **viewport**. After M6, the viewport track V0–V5 ([milestones.md](milestones.md); ADRs [0006](adr/0006-viewports.md)–[0009](adr/0009-reuse-not-fork.md)) is the priority and replaces M8–M10. Evidence: spikes [R15](spikes/2026-10-04-r15-encode-budget.md) (encode budget on the M4 Max) and [R16](spikes/2026-10-04-r16-clients-and-prior-art.md) (Windows App iPadOS, Jump Desktop, macrdp, IronRDP 0.13).

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
| V0–V5 | Viewport track | **next**: V0 iPad probe ([tasks/v0.md](tasks/v0.md)) |
| 7 | Clipboard | after V3 |
| 8–10 | Resize, multimon, EGFX | folded into V1, V3, V4 |
| 11–12 | Audio, daemon | after V3 |

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
just live-check                    # probe + serve + headless client: input + T1-PERF-02/03/04 (docs/live-check.md)
```

CI (`.github/workflows/test.yml`, 2026-10-04) runs `just test` on `macos-15` for every PR and push to main.

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
- Capture is **first display only** until V1. On this lab Mac the first `SCDisplay` is an external 1600×1200 panel, not the built-in.
- Changing iPad resolution must **reconfigure SCK / RDP framebuffer** (V1), never `CGDisplaySetDisplayMode` ([ADR 0006](adr/0006-viewports.md) keeps that forbidden).
- Encode budget (spike R15): one M4 Max engine cannot do 4K at 60 fps; tile across both engines or drop the unfocused viewport to 30 fps.
- Prior art: macrdp's `docs/known-quirks.md` documents many macOS traps (symbolic hotkeys, virtual-display HiDPI, Microsoft-client H.264 color). Read it before V1–V4 work ([ADR 0009](adr/0009-reuse-not-fork.md)).

## Next (priority)

1. **V0** ([tasks/v0.md](tasks/v0.md)): capability log in the engine, then one iPad session that scores M6 input and answers the Windows App questions. `just live-check` (2026-10-04) already passes M6 input on the server side.
2. **V1**: `DisplayRegistry` + serve any display + client-requested size (`with_honor_client_desktop_size`, RDPEDISP) with GPU scaling and aspect-fit bars. Never change the Mac's display modes.
3. **V2** switching → **V3** concurrent viewports (ABI v2, `run_connection` per connection) → **V4** H.264 (EGFX AVC420) + client-side cursor + `EncodeScheduler`.
4. **V5** native iPad client only if the owner accepts [ADR 0008](adr/0008-native-ipad-client.md). M7 clipboard, M11 audio, M12 daemon after V3.

## Tests that must stay true

- `just test` green, TCC-free.
- No new ABI methods “for later.”
- `FrameSource` still only `nextFrame()`. `InputSink` still only `handle(_:)`.
- No `ClipboardBridge` / `AudioSource` / `AvcFrameSink` until their first failing test.
