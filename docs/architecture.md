# Architecture

mrdpd is a Swift application that captures and injects on macOS, plus a Rust protocol engine behind a versioned C ABI.

```text
Windows App / FreeRDP / IronRDP headless
        │  B1  RDP over TLS + NLA
        ▼
┌───────────────────────┐
│  Engine dylib         │  IronRDP or StubEngine
│  mrdpd_engine.h       │
└──────────┬────────────┘
           │  B2  C ABI
           ▼
┌───────────────────────┐
│  EngineKit (Swift)    │  thin, version-checked wrapper
└──┬─────┬──────┬────┬──┘
   │     │      │    │
   │B3   │B4    │B5  │B6     B5/B6 do not exist as types until M7/M11
   ▼     ▼      ▼    ▼
Frame  Input  Clip Audio
Source Sink   (later)
   │     │
   ▼     ▼
SCK   CGEvent
```

## Boundaries

| ID | Name | Contract document | Test double | Real implementation |
| --- | --- | --- | --- | --- |
| B1 | Wire protocol | MS-RDPBCGR + channels in spec | Headless IronRDP client | Windows App, FreeRDP |
| B2 | Engine FFI | [abi.md](abi.md) + `include/mrdpd_engine.h` | StubEngine dylib | `mrdpd-engine` (IronRDP) |
| B3 | FrameSource | Swift protocol in CaptureKit | `SyntheticFrameSource` | `SCKFrameSource` (M4) |
| B4 | InputSink | Swift protocol in InputKit | `RecordingInputSink` | `CGEventInputSink` (M6) |
| B5 | ClipboardBridge | extracted M7 | `InMemoryClipboard` | `PasteboardClipboard` |
| B6 | AudioSource | extracted M11 | `ToneAudioSource` | `SCKAudioSource` |

B2 is the swap point. FreeRDP or a future Swift protocol stack must pass the same ABI contract tests. Swift above EngineKit must not import IronRDP types.

## Module graph (constituents, not layers)

Build and test in this order. A box may not depend on a box to its right until its own contract is green.

```text
Frame, InputEvent, EngineError     value types (M0)
        │
        ├─ FrameSource             protocol (M0)
        ├─ InputSink               protocol (M0)
        └─ mrdpd_engine.h v1       C ABI (M0)
                │
                ├─ SyntheticFrameSource, RecordingInputSink, StubEngine
                ├─ EngineKit (Swift loader + callbacks)
                └─ keymap tables (M3, pure data)
                        │
                        ├─ SCKFrameSource (M4)
                        ├─ ironrdp-backed engine (M1)
                        └─ CGEventInputSink (M6)
                                │
                                └─ app wiring (M5 view, M6 control)
```

Clipboard, layout, AVC, and audio attach as new segregated protocols, never as methods piled onto `Engine` or `FrameSource`.

## Process and privileges

- The process is a user Launch Agent, not a root Launch Daemon. ScreenCaptureKit and TCC do not work from a daemon in the traditional Unix sense.
- Screen Recording TCC is required for B3 real capture.
- Accessibility TCC is required for B4 real injection.
- FileVault pre-boot is unreachable. Documented limitation (`OUT-03`).

## Encoding path

- T1: Swift pushes BGRA frames (dirty rects) through `mrdpd_engine_push_frame`. The engine encodes RemoteFX / RLE.
- T2: Swift encodes H.264 via VideoToolbox and pushes annex-B (or engine-agreed) access units through a **new** ABI function added in M10, `mrdpd_engine_push_avc_frame`. FrameSource does not grow an `encodeH264` method.

## Display topology

- One `SCStream` per `SCDisplay`.
- Frames and dirty rects are translated into one RDP virtual-desktop coordinate space (primary origin 0,0; others may be negative).
- Dynamic single-monitor resize is T1 (`T1-MON-01`).
- Static and dynamic multimon are T2 (`T2-MON-*`), after the M1 R1 spike.

## What the C ABI is not

It is not a grab bag of macOS. No ScreenCaptureKit types, no `CGEvent`, no pasteboard. The engine sees bytes, rects, scancodes, and clipboard formats. macOS stays in Swift.
