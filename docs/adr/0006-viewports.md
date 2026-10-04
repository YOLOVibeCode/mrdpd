# ADR 0006: Viewports — one console, many independent views

Status: proposed (accepted when the PR that adds it merges)
Date: 2026-10-04
Supersedes: [0004](0004-single-console-session.md) in part — the "one active client" rule. One logged-in console user (OUT-02) stands.

## Context

Target scenario (owner, 2026-10-04): a MacBook Pro with three displays (built-in 3456×2234 Retina and two 1600×1200-point externals). On the other end, an iPad Pro with an external 4K monitor. Each client screen must show **any** Mac display, **independently** of the other screen, and the owner must be able to **switch** which Mac display a screen shows from the screen they are looking at.

Today mrdpd serves one connection, captures only the first `SCDisplay`, and forces the session size to that display's size (3360×1890 on the iPad run).

Facts from [spike R16](../spikes/2026-10-04-r16-clients-and-prior-art.md):

- Windows App on iPadOS has no multi-monitor, so two client screens means two sessions.
- IronRDP 0.13 exposes `run_connection(stream)` and `with_honor_client_desktop_size`.
- No existing macOS server routes displays to client screens or switches them in-session.

## Decision

1. **Model.** The host has a `DisplayRegistry` (physical and, behind a flag, virtual Mac displays, with stable IDs and the Mac arrangement) and one console **Session** with up to four **Viewports**. A viewport is one client screen:
   - one RDP connection, or
   - one monitor of a multi-monitor RDP connection (desktop clients, T2), or
   - one native-client window ([ADR 0008](0008-native-ipad-client.md)).

   A viewport has a source display, a size in client pixels, an fps cap, and a focus flag.
2. **Independent, switchable sources.** Each viewport's source can be changed at runtime without touching other viewports. Two viewports may show the same display.
3. **The client decides the size; the Mac never changes mode.** The viewport size comes from the client:
   - the connect-time desktop size (`with_honor_client_desktop_size`),
   - RDPEDISP resizes,
   - native window size.

   ScreenCaptureKit captures the source at its backing (Retina) resolution and scales it to the viewport on the GPU. The image is aspect-fit with bars (stretch optional). Mac display modes are never changed (no `CGDisplaySetDisplayMode`).
4. **Input.** Each viewport has its own `DisplayMap` from viewport pixels (minus bars) to the source display's global points. There is one Mac cursor and one keyboard focus. The viewport that sent the most recent input owns the cursor, with 500 ms hysteresis so two viewports never fight.
5. **Navigation is server-side and works with any client.** It is composited per viewport after capture: never on the Mac's physical screens, never into other viewports.
   - **Hotkeys**, intercepted by the host and not injected:
     - Ctrl+Option+1…9: show display N.
     - Ctrl+Option+[ and ]: previous or next display in arrangement order.
     - Ctrl+Option+0: overview.

     Frozen only after the V0 device check confirms Windows App on iPadOS passes them through.
   - **HUD**: the display's name and position, shown in that viewport for ~1 s after a switch.
   - **Overview**: a live grid of every display in that viewport. A click or tap selects one.
6. **One process, one listener, one IronRDP server per connection.** The engine accepts sockets itself and runs `run_connection` for each on its own thread and current-thread runtime (IronRDP's server future is `!Send`).
   - Captures are shared: one SCK stream per (display, output size), reference-counted by viewports.
   - Encoding is shared through the `EncodeScheduler` ([ADR 0007](0007-h264-encode-scheduler.md)).
7. **ABI v2.** Connection handles cross the C ABI:
   - connect info: requested size, monitors, keyboard layout, codec caps;
   - per-connection frame push;
   - per-connection input and layout callbacks.

   It is specified in [abi.md](../abi.md) first, when V1 needs the connect-info callback. v1 keeps working until then (AGENTS.md: no ABI "for later").

## Consequences

- T1-SEC-03 changes from "max one active client" to "one console user, up to four concurrent viewports from the same authenticated principal" ([spec.md](../spec.md)).
- New IDs T1-VP-01…06 and T2-VP-07. T1-MON-01 (resize) becomes part of T1-VP-02. T2-MON-01…03 (desktop multi-monitor) become "one viewport per client monitor" and stay T2.
- With Windows App alone the owner gets one Mac display per Windows App window. A second simultaneous screen needs either a second Windows App window (unverified, R16) or the native client.
- Virtual displays stay behind a flag ([ADR 0005](0005-private-virtual-display.md)). On macOS 26 they are 1:1 only (no HiDPI, R19). Scaled physical HiDPI displays are the crisp default; virtual displays are for lid-closed or monitors-off use, or extra screens only the iPad sees.

## Rejected

- **RDP multi-monitor for the iPad.** Windows App on iPadOS has none.
- **Process per connection.** Simple with ABI v1, but no shared capture, no central encode scheduling, and cross-process switching and overview.
- **Changing Mac display modes to fit the client.** It moves the owner's windows and fights physical panels (the [checkpoint](../checkpoint.md) already forbade this without an ADR; this ADR keeps it forbidden).
- **Drawing the HUD or overview as real macOS windows** (the macrdp HUD approach). They would show on the physical display and in every viewport of that display.
