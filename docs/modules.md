# Constituent modules (build order)

Nothing here is a “layer.” Each row is a testable element. Do not implement a row until the rows above it that it depends on are contract-green.

## Always (M0)

| Module | Kind | Tests | Spec IDs |
| --- | --- | --- | --- |
| `Frame` | value type | stride, dirty union, 2×2 fixture | T1-GFX-01 |
| `InputEvent` | value type | key/mouse equality | T1-IN-01 |
| `mrdpd_engine.h` v1 | C ABI | version, start/stop, bind, poison-after-return | T1-GFX-01, T1-SEC-04 |
| StubEngine | dylib | same ABI suite | (all v1 ABI) |
| `FrameSource` | protocol | SyntheticFrameSource | T1-GFX-01 |
| `InputSink` | protocol | RecordingInputSink | T1-IN-01 |
| EngineKit | Swift wrapper | dlopen version check, push + callback hop | B2 |

## Next (M1–M6)

| Module | Depends on | Spec IDs |
| --- | --- | --- |
| mrdpd-engine (IronRDP) — M1 | ABI v1 | T1-SEC-01/02/03, T1-GFX-01 |
| Headless harness — M1/M2 | engine | T1-GFX-01, T1-GFX-03 |
| `mrdpd-pattern` lab bin — M2 | engine + 1080p fixture | T1-GFX-01, T1-SEC-04 |
| `UsKeymap` — M3 | InputEvent | T1-IN-02 |
| DirtyRects + CaptureFrame | Frame | T1-GFX-01, T1-GFX-04 |
| SCKFrameSource | FrameSource | T1-GFX-01, T1-GFX-04 dirty list |
| FramePacer | — | T1-GFX-04 cap 60 |
| SCKSettings + cursor | SCKFrameSource | T1-GFX-05 |
| FramePump + `mrdpd-serve` | FrameSource, EngineKit, SCK | T1-GFX-01 live, T1-SEC-04 |
| DisplayMap + InjectionPlan | InputEvent | T1-IN-03, T1-IN-04 |
| CGEventInputSink | InputSink, keymap, DisplayMap | T1-IN-04 |
| App session (one client) | EngineKit | T1-SEC-03 |

## Extract later (not types today)

| When | Protocol | First test |
| --- | --- | --- |
| M7 | `ClipboardBridge` | string round-trip T1-CLP-01 |
| V1 | `DisplayRegistry`; connect-info callback (ABI bump); aspect-fit `DisplayMap` | T1-VP-01, T1-VP-02 |
| V2 | `ViewportRouter` (B7), hotkey matcher, overlay compositor | T1-VP-03, T1-VP-04 |
| V3 | ABI v2 connection handles; focus/cursor arbiter | T1-VP-05, T1-VP-06 |
| V4 | Viewport encoder (B8, replaces the `AvcFrameSink` plan), `EncodeScheduler`, `CursorSource` | T1-GFX-06…08 |
| V5 | `ViewportProtocol` package, native front end (if ADR 0008 accepted) | T2-NAT-01… |
| after V4 | `MonitorLayout` for desktop GCC multimon | T2-MON-01…03 |
| M11 | `AudioSource` | T2-AUD-01 |
| M12 | config, Keychain, LaunchAgent | T1-OPS-* |

Resize (now V1) and connection handles (V3) are additive ABI changes. Each is a version bump per [abi.md](abi.md), not a method secretly added to `push_frame`.
