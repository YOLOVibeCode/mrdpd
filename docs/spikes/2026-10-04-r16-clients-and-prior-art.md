# Spike R16: Clients and prior art for "two client screens, any Mac display"

Date: 2026-10-04
Question: For the target scenario (iPad Pro + external 4K; each client screen shows any Mac display, switchable), what can existing clients do, what already exists on the server side, and what does the current IronRDP release give us?
What we ran: documentation and source review (web, 2026-10-04); clone of `clintcan/macrdp` at `c47e371` (2026-10-02); source inspection of `ironrdp-server` 0.13.0 and `ironrdp-acceptor` 0.10.0 from the local Cargo registry. No device was available, so items marked **verify** need the iPad (see [tasks/v0.md](../tasks/v0.md)).

## A. Windows App on iPadOS (Microsoft Learn)

Sources: [compare-platforms-features](https://learn.microsoft.com/en-us/windows-app/compare-platforms-features) (updated 2026-09-18), [display-settings, iOS/iPadOS tab](https://learn.microsoft.com/en-us/windows-app/display-settings?tabs=ios-ipados) (updated 2026-08-11), [input, iOS/iPadOS tab](https://learn.microsoft.com/en-us/windows-app/input-keyboard-mouse-touch-pen?tabs=ios-ipados).

| Capability | iOS/iPadOS | Consequence for mrdpd |
| --- | --- | --- |
| Multiple monitors (one session spanning screens) | ❌ | iPad screen + 4K cannot be two monitors of one RDP session. Two screens means two sessions. |
| External monitor | ✅ | With Stage Manager and a wired display: "you can use the external display for the remote session while using your iPad with other apps, including multi-tasking, windows resizing, and dynamic resolution across the iPad and external display." Without Stage Manager: session on the external display at native resolution, iPad becomes a trackpad. |
| Dynamic resolution | table says ❌; Stage Manager text says resizing works | **verify**: RDPEDISP from a resized Stage Manager window. Either way, honor the connect-time size. |
| Two sessions visible at once (two windows) | not documented | **verify** (Stage Manager ••• → New Window). The decisive unknown for "both screens with Windows App". |
| Keyboard | Cmd = Windows key, but "Windows App automatically maps common shortcuts found in iOS/iPadOS so they work in Windows" (Cmd+C/X/V/A/Z/F) | **verify** what the Mac receives for Cmd+C (likely Ctrl+C). Mac-correct shortcuts may need a server-side remap. |
| H.264 (AVC420) decode | not documented | **verify** by logging the client's EGFX CapsAdvertise on first connect. |
| Mouse/trackpad, touch, multi-touch, pen | ✅ | Trackpad scroll arrives as wheel notches (no precise/momentum scrolling). |

## B. Jump Desktop (closest off-the-shelf product)

Source: [Switch and arrange remote displays](https://docs.jumpdesktop.com/viewer/session/displays/).

- Display switching, displays in separate windows, and setting host display resolution are **Fluid-only** (Jump Desktop Connect host), not RDP.
- "iPhone, iPad, and Android show the session in a single window." iPad "supports several open sessions simultaneously."
- "Use External Display takes over the external display; keep it off if you use Stage Manager."
- Proprietary, and it does not offer two independent Mac displays on two iPad screens. Useful to try the switching UX today.

## C. Open-source macOS RDP servers

| Project | License | Status | Has | Lacks |
| --- | --- | --- | --- | --- |
| [clintcan/macrdp](https://github.com/clintcan/macrdp) | MIT OR Apache-2.0 | v0.9.11, ~35k lines Rust, pushed 2026-10-02, 24 merged upstream IronRDP PRs | H.264 AVC420 via VideoToolbox through upstream `ironrdp-egfx`; real cursor shapes; clipboard (text, image, RTF, HTML, files); audio, mic; drive, USB, smart-card, camera redirection; RDPEDISP + client-size adopt with letterbox; `CGVirtualDisplay` headless modes; UDP multitransport; PAM auth; audit log | "no multi-monitor"; "one session at a time"; no display switching |
| [x6nux/macrdp](https://github.com/x6nux/macrdp) | GPL-3.0 | last code push 2026-05-18 | H.264 + AVC444, HiDPI, clipboard, audio | multi-monitor, display selection |
| [CGKPK/RDPonMAC](https://github.com/CGKPK/RDPonMAC) | Apache-2.0 (README) | dormant since 2026-04-27 | libxrdp + SCK, display + input | everything else |

**No server routes Mac displays to client screens independently, and none switches displays in-session.** That is the gap mrdpd fills.

## D. IronRDP today (crates.io `ironrdp-server` 0.13.0, 2026-07-10)

- Feature `egfx` → `ironrdp-egfx` 0.3: server-side MS-RDPEGFX with AVC420 and AVC444. Active upstream (AVC444 mixed-codec PR #2002, H.264 ZGFX bypass #2003, Sept 2026).
- `RdpServer::run_connection(stream)` and `run_connection_with(stream, tls)` are public. We can own the accept loop and run one server instance per connection on its own thread.
- `RdpServerBuilder::with_honor_client_desktop_size`: adopt the client's requested size at connect.
- RDPEDISP `RdpServerDisplay::request_layout` (resize) exists. Static GCC multimon is still one monitor ([R1](2026-08-20-r1-static-multimon.md) unchanged).

## E. macOS facts learned the hard way by macrdp

Sources: `docs/known-quirks.md`, `docs/macos-gotchas.md`, `docs/video.md` in macrdp at `c47e371`.

- `CGVirtualDisplay` on macOS 26 is an Obj-C class (`initWithDescriptor:`, `applySettings:`). **HiDPI cannot be enabled**: three methods were tested on 26.4, and virtual displays are always 1:1 points to pixels. A virtual "4K" screen gives either tiny UI (3840×2160 at 1x) or soft upscaling (1920×1080 at 1x).
- Synthetic `CGEventPost` input does **not** trigger WindowServer symbolic hotkeys (Cmd+Tab, Cmd+`, Spotlight, screenshots). They need Accessibility-driven workarounds.
- Microsoft clients read AVC420 luma as full range: encode full-range BT.709. mstsc holds ~2 frames before presenting, so send flush frames after a change. Force an IDR every ~2 s.
- SCK delivers crisp backing-pixel (Retina) buffers when configured at backing size. The SkyLight cursor bitmap is already at backing scale; do not rescale it.

## Answer

- Windows App can carry **one Mac display per session window**. Whether two windows can run at once on one iPad is the key unknown. Without that, Windows App gives "one screen at a time, switchable".
- **A native iPad client is the only path that guarantees** two screens at once, Mac-correct modifiers, precise scrolling, and a real display picker ([ADR 0008](../adr/0008-native-ipad-client.md), proposed).
- Do not fork macrdp; port its lessons ([ADR 0009](../adr/0009-reuse-not-fork.md)).
- IronRDP 0.13 already has the pieces for per-connection viewports and H.264.

## Effect on spec / milestones

[ADR 0006](../adr/0006-viewports.md) through [ADR 0009](../adr/0009-reuse-not-fork.md); V-track in [milestones.md](../milestones.md); risks R16–R21.

## Follow-up

The V0 device checklist in [tasks/v0.md](../tasks/v0.md). Re-check macrdp and IronRDP releases quarterly (R21).
