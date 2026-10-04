# Architecture

mrdpd is a Swift host that captures, encodes, and injects on macOS. It serves **viewports**, meaning client screens that each show any Mac display, through two front ends: an RDP engine (IronRDP behind a versioned C ABI) and, if [ADR 0008](adr/0008-native-ipad-client.md) is accepted, a native protocol for an iPad client.

Revised 2026-10-04 for the target scenario: [ADR 0006](adr/0006-viewports.md)–[0009](adr/0009-reuse-not-fork.md), spikes [R15](spikes/2026-10-04-r15-encode-budget.md) and [R16](spikes/2026-10-04-r16-clients-and-prior-art.md).

## Target scenario

```text
  Mac (one console user)                         Owner, away from the desk
  ┌──────────────┬──────────────┬──────────────┐   ┌──────────────┐  ┌──────────────────────┐
  │ Display 1    │ Display 2    │ Display 3    │   │ iPad Pro 13" │  │ external 4K monitor  │
  │ built-in     │ Sceptre (L)  │ Sceptre (R)  │   │ viewport A   │  │ viewport B           │
  └──────────────┴──────────────┴──────────────┘   │ shows any    │  │ shows any display,   │
                                                   │ display      │  │ independently of A   │
                                                   └──────────────┘  └──────────────────────┘
  Switch from the screen you're on: hotkey · HUD · overview grid (any client) or picker strip (native client)
```

## Components

```text
 iPad screen          external 4K           any RDP client (Windows App, FreeRDP, mstsc)
 (viewport A)         (viewport B)          (viewport C …)
      │  native client (ADR 0008)                 │
      │  QUIC + TLS 1.3                           │  RDP over TLS + NLA  (B1)
      ▼                                           ▼
┌───────────────────────┐             ┌──────────────────────────────┐
│ NativeFrontEnd (Swift) │             │ Engine dylib (IronRDP)        │  one RdpServer per
│ ViewportProtocol pkg   │             │ accept loop, run_connection   │  connection, own thread
└───────────┬───────────┘             └──────────────┬───────────────┘
            │                          B2  C ABI v2 (connection handles)
            │                                         │
            ▼                                         ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ SessionHub — one console session, connections → Viewports (ADR 0006)          │
│   ViewportRouter: source per viewport, hotkeys, HUD, overview, focus/cursor   │
└──────┬──────────────────┬───────────────────┬────────────────────┬───────────┘
       │                  │                   │                    │
┌──────▼───────┐  ┌───────▼────────┐  ┌───────▼─────────┐  ┌───────▼──────────────┐
│DisplayRegistry│  │ CaptureHub      │  │ EncodeScheduler │  │ InputRouter          │
│ physical +    │  │ SCK stream per  │  │ VideoToolbox    │  │ per-viewport         │
│ virtual (flag)│  │ (display, size, │  │ H.264 slots =   │  │ DisplayMap → CGEvent │
│ arrangement,  │  │ tile); backing  │  │ HW engines;     │  │ hotkey intercept;    │
│ change events │  │ px, GPU scaled  │  │ focus policy    │  │ CursorSource (shape) │
└───────────────┘  └─────────────────┘  └─────────────────┘  └──────────────────────┘
```

| Component | Owns | Today | Arrives |
| --- | --- | --- | --- |
| DisplayRegistry | Mac displays: stable IDs, names, arrangement, backing size, reconfiguration events. Virtual displays behind a flag ([ADR 0005](adr/0005-private-virtual-display.md); 1:1 only on macOS 26) | first `SCDisplay` only | V1 |
| CaptureHub | One `SCStream` per (display, output size, tile), reference-counted. Captures at backing pixels; SCK scales on the GPU; `sourceRect` cuts tiles. Overlays (HUD, overview) are composited per viewport after capture | one stream, native size | V1 / V2 |
| SessionHub + ViewportRouter | Connections to viewports; source switching; hotkeys; HUD; overview; focus (most recent input) and cursor ownership (500 ms hysteresis) | one connection | V1–V3 |
| EncodeScheduler | Hardware H.264 sessions, sized to the engine count; focused viewport at 60 fps, tiled if > ~5.7 Mpx; others ≤ 30 fps; drop-oldest, one frame deep ([ADR 0007](adr/0007-h264-encode-scheduler.md)) | none (RemoteFX in engine) | V4 |
| InputRouter + CursorSource | Per-viewport `DisplayMap`; CGEvent posting; hotkey interception; symbolic-hotkey workarounds; cursor shape and position for client-side cursors | one `DisplayMap`, cursor composited | V1–V4 |
| RDP engine | IronRDP 0.13: TLS, NLA, FastPath input, RDPEDISP, EGFX AVC420, RemoteFX fallback | ABI v1, sequential `run()` | ABI v2 at V1/V3 |
| NativeFrontEnd + `mrdpd-ipad` | QUIC viewport protocol and the iPad app (proposed) | — | V5 |

## Boundaries

| ID | Name | Contract document | Test double | Real implementation |
| --- | --- | --- | --- | --- |
| B1 | RDP wire | MS-RDPBCGR, RDPEDISP, RDPEGFX | headless IronRDP client (`tests/common`, `live_check.rs`) | Windows App, FreeRDP |
| B1n | Native wire (proposed) | `ViewportProtocol` package docs | in-process loopback transport | `mrdpd-ipad` |
| B2 | Engine FFI | [abi.md](abi.md) + `include/mrdpd_engine.h` (v1 → v2) | StubEngine dylib | `mrdpd-engine` (IronRDP) |
| B3 | FrameSource | Swift protocol in FrameKit (`nextFrame()` only) | `SyntheticFrameSource` | `SCKFrameSource`, per (display, size) from V1 |
| B4 | InputSink | Swift protocol in InputKit (`handle(_:)` only) | `RecordingInputSink` | `CGEventInputSink` |
| B5 | ClipboardBridge | extracted M7 | `InMemoryClipboard` | `PasteboardClipboard` |
| B6 | AudioSource | extracted M11 | `ToneAudioSource` | `SCKAudioSource` |
| B7 | Viewport control | extracted V1 on its first failing test | `RecordingViewportRouter` | `ViewportRouter` |
| B8 | Viewport encoder | extracted V4 on its first failing test (replaces the M10 `AvcFrameSink` plan) | `RecordingEncoder` | VideoToolbox H.264 |

B2 is still the swap point for the RDP engine. Swift above EngineKit never imports IronRDP types. Every new protocol (B7, B8) is extracted by its first failing test, with no methods "for later" ([ADR 0003](adr/0003-tdd-and-isp.md)).

## A viewport switch, end to end

1. Windows App on the 4K sends Ctrl+Option+2. The engine raises `on_key(conn B, …)`, and EngineKit hops to the host.
2. InputRouter matches the hotkey, does **not** inject it, and asks ViewportRouter for "viewport B → display 2".
3. ViewportRouter re-points B: CaptureHub reuses or starts the (display 2, 3840×2160) stream and releases the old one if unused; `DisplayMap(B)` is rebuilt; EncodeScheduler forces an IDR for B.
4. The next frames for B carry display 2 with the HUD "Display 2 · Sceptre (left)" for ~1 s. Viewport A never notices.

## Encoding path

- **T1 (from V4):** VideoToolbox H.264 per viewport (and per tile), scheduled by EncodeScheduler. Carried as EGFX AVC420 for RDP clients and as access units over the native protocol. RemoteFX is the automatic RDP fallback.
- **Today:** Swift pushes BGRA frames and dirty rects through `mrdpd_engine_push_frame`; the engine encodes RemoteFX (QoiZ compiled out).
- **Cursor:** composited into frames today (T1-GFX-05). It becomes client-side at V4 (T1-GFX-06): pointer PDUs or the native cursor stream, removed from captured frames.

## Display topology

- Viewports, not one virtual desktop. Each viewport has exactly one source display (or the overview).
- RDP desktop clients with several monitors (T2): one viewport per client monitor, one EGFX surface each. Static GCC multimon still needs the acceptor change from spike R1.
- The Mac's display modes are never changed. Client size is reached by GPU scaling with aspect-fit bars.
- Virtual displays (flag): for lid-closed or monitors-off use and screens only a client sees. They are 1:1 on macOS 26; a physical HiDPI display or an HDMI dummy plug with HiDPI modes is the crisp option.

## Process and privileges

- The host is a user Launch Agent, not a root Launch Daemon. ScreenCaptureKit and TCC do not work from a daemon.
- Screen Recording TCC is required for real capture (B3) and Accessibility TCC for real injection (B4), on the process that runs the host.
- FileVault pre-boot is unreachable (`OUT-03`). Synthetic input cannot reach the login window or secure fields.

## What the C ABI is not

It is not a grab bag of macOS. No ScreenCaptureKit types, no `CGEvent`, no pasteboard. The engine sees connections, bytes, rects, scancodes, encoded access units, and clipboard formats. macOS stays in Swift.
