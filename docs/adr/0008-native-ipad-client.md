# ADR 0008: Native iPad client over a native viewport protocol

Status: **accepted** — owner, 2026-10-04 ("yes, build the iPad app"). Team N42FM5L5KD for signing.
Date: 2026-10-04

## Context

The target scenario ([ADR 0006](0006-viewports.md)) needs two client screens at once, each showing a different Mac display, with fast switching. With Windows App on iPadOS ([spike R16](../spikes/2026-10-04-r16-clients-and-prior-art.md)):

- **No multi-monitor.** Two screens means two sessions, and two simultaneous Windows App windows are undocumented.
- **Cmd is remapped.** Common shortcuts are remapped for Windows, so the Mac likely receives Ctrl+C for Cmd+C.
- **Scrolling is coarse.** Trackpad scrolling arrives as wheel notches, with no momentum.
- **No picker.** There is no client-side UI for picking a display.

Server-side hotkeys, HUD, and overview (ADR 0006) make Windows App usable for one screen at a time. They cannot create a second window on the client.

## Decision (proposed)

1. Build **`mrdpd-ipad`**, a SwiftUI/UIKit app for iPadOS 26+.
   - **One `UIWindowScene` per viewport.** In Stage Manager, put one window on the iPad screen and one on the 4K monitor.
   - **Picker.** Each window has a picker strip of live display thumbnails, plus keyboard shortcuts for switching.
   - **Input.** Hardware keyboard sent as HID usages with true Cmd/Option/Control. Pointer can be absolute, or relative with pointer lock. Scrolling is continuous with phases (Mac momentum). Pinch can be added later.
   - **Rendering.** Clipboard both ways. A local cursor at the display's refresh rate. VideoToolbox decode to `AVSampleBufferDisplayLayer`.
2. Add a **native viewport protocol** over QUIC, using Network.framework on both ends with TLS 1.3. It has four parts:
   - **Control stream**: displays (ID, name, arrangement, size), thumbnails, subscribe / switch / resize / focus, clipboard.
   - **Video**: per viewport and per tile, H.264 (HEVC opt-in) access units, one QUIC stream per frame. Late frames are dropped.
   - **Input**: a high-priority stream.
   - **Cursor**: shape plus position.
3. **Shared Swift package `ViewportProtocol`**, used by the host and the client. Message and framing contract tests run in `just test` on macOS (TCC-free).
4. **Pairing.** The host shows a 6-digit code once. The client then stores the host key; the host stores a per-device key. The listener binds loopback or an explicit interface (Tailscale) like RDP (T1-SEC-04); it never binds 0.0.0.0.
5. **RDP stays.** It works with any client and needs no install. The host core (capture, scheduler, input, viewports) is shared; the native front end is a thin Swift module beside the IronRDP engine.

## As built (v0.1, 2026-10-04)

- **Transport: TCP + TLS 1.2 ECDHE-PSK** (`TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256`), one connection per window, not QUIC. Network.framework supports it on both platforms without certificates. The server picks the key by device identity, so wrong or unknown keys fail the handshake. One connection per window means a busy 4K stream never blocks another window's input. QUIC can replace it behind `FramedConnection` later.
- **Pairing: no 6-digit code.** A short code used directly as the key would allow offline guessing. Instead the Mac generates a 32-byte key per iPad and hands it over as an `mrdpd://pair` link: Universal Clipboard paste, QR scan, or the Camera app. The app confirms the Mac's name and address before storing a link opened from outside.
- **Code**:
  - `Packages/ViewportKit`: `ViewportProtocol`, `ViewportTransport`, `ViewportClient`.
  - `Sources/HostKit` + `mrdpd-host`.
  - `apps/ipad` (XcodeGen).
  - Guide: [ipad.md](../ipad.md).
- **Built ahead of V1–V4 at the owner's request.** The viewport core (display registry, per-window capture at client size, H.264, encode scheduler, input injection, cursor) is Swift in `HostKit`. RDP reuses it in V1–V4.

## Consequences

- An Apple Developer account is needed to keep the app installed beyond the 7-day free provisioning (TestFlight or ad hoc).
- A second wire protocol, kept thin: no codec, auth, or capture logic of its own.
- New IDs T2-NAT-01…06 in [spec.md](../spec.md) and milestone V5.

## Alternatives

- **Windows App only.** Cannot guarantee two screens at once; Cmd is remapped; scrolling is notches. Stays supported as the zero-install path.
- **Jump Desktop.** Proprietary; switching only with its own host (Fluid), not RDP; a single window per session on iPad.
- **An RDP client of our own on iOS** (IronRDP client compiled for iOS). Far heavier than QUIC plus H.264, and Mac-semantics input would still need private RDP extensions.
