# mrdpd — Functional specification

Status: approved as working spec; IDs are stable. Change IDs only with an ADR.

Companion docs: [method.md](method.md), [architecture.md](architecture.md), [traceability.md](traceability.md), [abi.md](abi.md).

## 1. Purpose and scenario

mrdpd is a native RDP **server** for macOS. A standards-compliant RDP client (primary: Windows App on iPad; secondary: Windows App on macOS/Windows, FreeRDP) connects to the Mac and sees and controls the logged-in user's console session.

Primary scenario: full control of the Mac from an iPad over LAN or tunneled WAN (Tailscale/SSH), including the repair-window / lid-closed / headless case.

Secondary scenario: desktop-class clients (Mac/Windows) using multi-monitor, high-fidelity sessions.

**Target scenario (owner, 2026-10-04; [ADR 0006](adr/0006-viewports.md)):** a MacBook Pro with three displays, driven from an iPad Pro that has an external 4K monitor. Each client screen is an independent **viewport** that can show any Mac display, and the owner switches what a screen shows from that screen. Two client screens at once need two sessions (Windows App on iPadOS has no multi-monitor) or the native client ([ADR 0008](adr/0008-native-ipad-client.md), proposed).

## 2. Tiers of done

A tier is done when every ID in it is `interop-green` in [traceability.md](traceability.md) on the clients listed for that ID.

- **T1 — Core session** (must have): daily use of the Mac from the iPad.
- **T2 — Full desktop parity** (target of this spec): multi-monitor, H.264, audio, clipboard files, multitouch.
- **T3 — Device redirection** (stretch; each item is its own macOS project): client mic/camera/drives as devices on the Mac. **Not scheduled before M12.**
- **OUT — Non-goals** with rationale. Revisit only with an ADR.

## 3. Target client matrix

- **C-IPAD** Windows App, iOS/iPadOS — primary T1. No true multimon. Strict RDP.
- **C-DESK** Windows App, macOS + Windows — T2 multimon.
- **C-FREERDP** FreeRDP — second stack; CI where possible.
- **C-HEADLESS** IronRDP headless — CI handshake, BMP, scripted input; `just live-check` live loop.
- **C-NATIVE** `mrdpd-ipad` over the native viewport protocol — **proposed** ([ADR 0008](adr/0008-native-ipad-client.md)). Two screens at once, Mac-correct keys, precise scrolling.

## 4. Features (stable IDs)

Each ID: protocol, macOS approach, engine status, tier, milestone.

### 4.1 Connection, security, session

| ID | Requirement | Protocol / API | Engine | Tier | Milestone |
| --- | --- | --- | --- | --- | --- |
| T1-SEC-01 | TLS 1.2/1.3 Enhanced RDP Security. First-run self-signed cert; optional cert paths in config | MS-RDPBCGR | built-in | T1 | M1 |
| T1-SEC-02 | NLA (CredSSP / NTLMv2). Credentials from mrdpd store, **not** the macOS login password | CredSSP, sspi-rs | `with_hybrid` | T1 | M1 |
| T1-SEC-03 | Single console session: the logged-in user. Up to four concurrent **viewports** from the same authenticated principal ([ADR 0006](adr/0006-viewports.md); was "max one active client", ADR 0004) | session | `run_connection` per connection | T1 | M1 / V3 |
| T1-SEC-04 | Bind-address policy: default localhost + explicit allowlist (or Tailscale iface). Port configurable (3389) | config | listen | T1 | M1 / M12 |
| T1-SEC-05 | Rate limit + lockout on failed auth | local | app | T1 | M12 |
| T1-SEC-06 | No plaintext RDP in release builds | build flag | n/a | T1 | M12 |
| T1-SEC-07 | Secrets in Keychain; config holds references | Keychain | n/a | T1 | M12 |
| T1-SEC-08 | Audit log: who / when / from-where / auth outcome | local | callbacks | T1 | M12 |
| T2-SEC-01 | Auto-reconnect cookies without re-auth loops | MS-RDPBCGR | **spike R5**: implement after M6 on IronRDP with `with_auto_reconnect_cookie` (not crates.io 0.13.0) | T2 | after M6 |
| T2-SEC-02 | Network autodetect / RTT feeds encoder | autodetect, echo | built-in TBD | T2 | M10 |
| T2-SEC-03 | Optional read-only second viewer | session | TBD | T2 | optional after M6 |

### 4.2 Graphics

| ID | Requirement | Protocol / API | Engine | Tier | Milestone |
| --- | --- | --- | --- | --- | --- |
| T1-GFX-01 | Push BGRA frames with stride + dirty rects into the engine | ABI v1 | consume frames | T1 | M0–M5 |
| T1-GFX-02 | RDP 6.0 bitmap + interleaved RLE fallback | MS-RDPBCGR | built-in; **not used** while the client advertises RemoteFX (M2) | T1 | M2 |
| T1-GFX-03 | RemoteFX (incl. progressive) default codec pre-EGFX | RemoteFX | built-in; M2 1080p E2E (QoiZ compile-out) | T1 | M2 / M5 |
| T1-GFX-04 | Damage-driven encode, frame pacing (cap 60, adaptive) | SCK dirty + pacer | n/a | T1 | M5 |
| T1-GFX-05 | Cursor composited into frames (until T1-GFX-06 replaces it per viewport) | SCK cursor | n/a | T1 | M5 |
| T1-GFX-06 | Client-side cursor: shape + position sent separately (RDP color pointer PDUs; native cursor stream); cursor removed from captured frames; hidden in viewports whose source does not hold the cursor | pointer PDUs | built-in | T1 | V4 |
| T1-GFX-07 | H.264 via VideoToolbox for every viewport: EGFX AVC420 for RDP (`ironrdp-server` feature `egfx`), access units for the native client; full-range BT.709; RemoteFX fallback for clients without AVC | MS-RDPEGFX | `ironrdp-egfx` 0.3 | T1 | V4 |
| T1-GFX-08 | `EncodeScheduler`: slots = hardware encode engines (measured); focused viewport 60 fps, tiled when > one engine's 60 fps capacity; other viewports ≤ 30 fps (≤ 15 with three); one frame deep, drop-oldest ([ADR 0007](adr/0007-h264-encode-scheduler.md), [spike R15](spikes/2026-10-04-r15-encode-budget.md)) | VideoToolbox | n/a | T1 | V4 |
| T2-GFX-01 | **Superseded by T1-GFX-06** (ADR 0007) | — | — | — | — |
| T2-GFX-02 | **Superseded by T1-GFX-07** (ADR 0007) | — | — | — | — |
| T2-GFX-03 | AVC444 after AVC420 is stable | MS-RDPEGFX | experimental | T2 | M10+ |

### 4.3a Viewports ([ADR 0006](adr/0006-viewports.md))

A viewport is one client screen: one RDP connection, one monitor of a multi-monitor RDP connection, or one native-client window. It has a source display, a size, an fps cap, and a focus flag.

| ID | Requirement | Protocol / API | Engine | Tier | Milestone |
| --- | --- | --- | --- | --- | --- |
| T1-VP-01 | Serve **any** Mac display, not only the first `SCDisplay`. `DisplayRegistry` with stable IDs, names, arrangement, backing size, reconfiguration events | SCK, CGDisplay | n/a | T1 | V1 |
| T1-VP-02 | Viewport size comes from the client (connect-time desktop size; RDPEDISP resize; native window size). Capture at backing pixels, GPU-scaled, aspect-fit with bars (stretch optional). Mac display modes never change. Input maps through the bars correctly | GCC, MS-RDPEDISP, SCK | `with_honor_client_desktop_size`, `request_layout` | T1 | V1 |
| T1-VP-03 | Switch a viewport's source at runtime without affecting other viewports. Host-intercepted hotkeys (Ctrl+Option+1…9, [ and ], 0 = overview; frozen after V0 device check) are never injected. HUD with the display name for ~1 s, composited only into that viewport | FastPath | n/a | T1 | V2 |
| T1-VP-04 | Overview: a live grid of all displays composited into the viewport; click or tap selects | FastPath | n/a | T1 | V2 |
| T1-VP-05 | Concurrent viewports: up to four connections at once, each with its own source and size; captures shared per (display, size) | `run_connection` | ABI v2 | T1 | V3 |
| T1-VP-06 | Focus and cursor arbitration: the viewport with the most recent input owns the Mac cursor (500 ms hysteresis); keyboard goes to the Mac's key window; focus drives encode priority | n/a | n/a | T1 | V3 |
| T2-VP-07 | Hotkey to move the frontmost Mac window to display N (Accessibility API) so work can cross viewports | AX | n/a | T2 | after V3 |

### 4.3 Display topology

RDP virtual desktop: primary at (0,0); others relative; negative origins allowed.

| ID | Requirement | Protocol / API | Engine | Tier | Milestone |
| --- | --- | --- | --- | --- | --- |
| T1-MON-01 | Single-monitor dynamic resize (client rotation / RDPEDISP one monitor). Delivered as part of T1-VP-02 | MS-RDPEDISP | implemented | T1 | V1 (was M8) |
| T2-MON-01 | Static multimon at connect (GCC monitor list) | GCC | **spike R1**: upstream acceptor / patch (not OUT) | T2 | M9 |
| T2-MON-02 | Dynamic add/remove/rearrange | MS-RDPEDISP | implemented | T2 | M9 |
| T2-MON-03 | One SCStream per SCDisplay; dirty rects translated into virtual-desktop space; Retina consistent | SCK | n/a | T2 | M9 |
| T2-MON-04 | Virtual displays when client wants more monitors than exist / lid closed (`CGVirtualDisplay`, flag); HDMI dummy plug documented fallback. macOS 26: 1:1 only, no HiDPI (R19) | private API **R3** | n/a | T2 | M9 |

iPad Windows App is single-monitor (informative). iPad still gets T1-MON-01 exact-fit resize.

### 4.4 Input

| ID | Requirement | Protocol / API | Engine | Tier | Milestone |
| --- | --- | --- | --- | --- | --- |
| T1-IN-01 | Engine delivers scancode + modifier events over ABI callbacks | FastPath | built-in | T1 | M3 |
| T1-IN-02 | RDP scancode → macOS virtual keycode table (US complete; others incremental) | data | n/a | T1 | M3 |
| T1-IN-03 | Mouse move / buttons / vertical wheel; Retina + origin mapping | FastPath | built-in | T1 | M3 / M6 |
| T1-IN-04 | CGEvent posting for key + mouse (Accessibility TCC) | CGEvent | n/a | T1 | M6 |
| T2-IN-01 | Unicode keyboard (TS_UNICODE) for IME | MS-RDPBCGR | TBD | T2 | after M6 |
| T2-IN-02 | Horizontal wheel + XButtons | FastPath | TBD | T2 | after M6 |
| T2-IN-03 | MS-RDPEI touch → gestures (two-finger scroll min; pinch best-effort) | MS-RDPEI | **spike R2**: upstream attach `RdpeiServer`; T1 fallback = wheel | T2 | after M6 |
| OUT-IN-01 | Pen frames | MS-RDPEI | — | OUT | — |

### 4.5 Clipboard (MS-RDPECLIP)

| ID | Requirement | Notes | Tier | Milestone |
| --- | --- | --- | --- | --- |
| T1-CLP-01 | UTF-16 ⇄ NSPasteboard string, both directions, delayed rendering | extract `ClipboardBridge` on first test | T1 | M7 |
| T2-CLP-01 | Images (DIB/PNG) + HTML | | T2 | M7+ |
| T2-CLP-02 | File group + stream ⇄ pasteboard promises; cancel large files | | T2 | M7+ |

### 4.6 Audio

| ID | Requirement | Notes | Tier | Milestone |
| --- | --- | --- | --- | --- |
| T2-AUD-01 | System audio via SCK (exclude mrdpd); PCM then AAC; `rdpsnd` | extract `AudioSource` on first test | T2 | M11 |
| T3-AUD-01 | Mic as virtual CoreAudio device | own project | T3 | after M12 |

### 4.7 Device redirection

| ID | Requirement | Tier |
| --- | --- | --- |
| T3-DEV-01 | Client drives via File Provider / NFS localhost | T3 |
| T3-DEV-02 | Camera via CMIO extension | T3 |
| OUT-DEV-01 | Smart card, printers, scanners, serial, USB, location | OUT |
| OUT-DEV-02 | Time zone: log client field only; no clock change | OUT |

### 4.7a Native client (proposed, [ADR 0008](adr/0008-native-ipad-client.md))

ADR 0008 accepted 2026-10-04; v0.1 built ([ipad.md](ipad.md)).

| ID | Requirement | Tier | Milestone |
| --- | --- | --- | --- |
| T2-NAT-01 | `ViewportProtocol` Swift package: control, video, input, cursor messages and framing; contract tests in `just test` | T2 | V5 |
| T2-NAT-02 | Transport + pairing: TLS 1.2 ECDHE-PSK over TCP (Network.framework), one random 32-byte key per device delivered as an `mrdpd://pair` link (paste / QR, confirmed on the iPad), explicit bind (loopback/Tailscale, never 0.0.0.0), unpair revokes within 2 s. QUIC later behind the same API | T2 | V5 |
| T2-NAT-03 | `mrdpd-ipad`: one window scene per viewport; works on the iPad screen and an external display under Stage Manager | T2 | V5 |
| T2-NAT-04 | Picker strip with live thumbnails plus switch shortcuts | T2 | V5 |
| T2-NAT-05 | Mac-correct input: HID usages with true Cmd/Option/Control; continuous scroll with phases; pointer lock option | T2 | V5 |
| T2-NAT-06 | Local cursor rendering and clipboard both ways | T2 | V5 |

### 4.8 Non-goals

| ID | Non-goal | Rationale |
| --- | --- | --- |
| OUT-01 | RemoteApp / RAIL | macOS window server; whole desktop only |
| OUT-02 | Multi-user sessions | macOS license / architecture |
| OUT-03 | Login window / FileVault pre-boot | unreachable third-party; **R9** |
| OUT-04 | RDP Gateway, farms, load balance | single host; Tailscale/SSH is WAN |
| OUT-05 | App Store distribution | private virtual display + TCC model |

## 5. Performance (acceptance)

| ID | Target | Tier | Measure |
| --- | --- | --- | --- |
| T1-PERF-01 | ≥ 30 fps 1080p-equivalent under motion on LAN | T1 | `just bench` M5+ |
| T1-PERF-02 | Input-to-photon < 80 ms on LAN | T1 | bench M6+ |
| T1-PERF-03 | Idle < 50 kbit/s | T1 | bench M5+ |
| T1-PERF-04 | CPU < 40% of one P-core idle 1080p | T1 | bench M5+ |
| T2-PERF-01 | Usable 1080p at 5 Mbit/s; degrade to 1.5 Mbit/s without stall | T2 | M10 |
| T2-PERF-02 | 2×1440p ≥ 20 fps combined LAN | T2 | M9 |
| T1-PERF-05 | Two viewports at once (3840×2160 + 2752×2064) on an M-series Max: focused viewport ≥ 50 fps and the other ≥ 25 fps under full motion, median encode latency < 25 ms each ([spike R15](spikes/2026-10-04-r15-encode-budget.md) baseline: 24/19/14 ms) | T1 | `just bench-encode`; `just live-check` at V4 |

## 6. Operations

| ID | Requirement | Milestone |
| --- | --- | --- |
| T1-OPS-01 | Launch Agent in GUI session (not root daemon) | M12 |
| T1-OPS-02 | Config: port, bind, creds refs, cert paths | M12 |
| T1-OPS-03 | TCC onboarding UX (Screen Recording, Accessibility) | M4 / M6 / M12 |
| T1-OPS-04 | Signed + notarized app **and** engine dylib, hardened runtime | M12 |
| T1-OPS-05 | pkg or Homebrew install; clean-VM checklist | M12 |

## 7. Verification rules

- Every T1/T2 ID has (a) a contract test at its boundary, (b) an E2E assertion or an explicit N/A, (c) an interop row when user-visible.
- Multimon goldens: distinct pattern per virtual monitor; RDPEDISP add/remove/rearrange round-trip.
- Performance IDs measured by `just bench`; numbers recorded per release.

## 8. Open spikes

See [risks.md](risks.md). R1, R2, R5 spikes are written (M1 DoD). R3 accepted as flag+dummy-plug. R4 accepted as RemoteFX fallback + engine swap. R15 (encode budget) and R16 (clients and prior art) written 2026-10-04 for the viewport track.
