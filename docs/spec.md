# mrdpd — Functional specification

Status: approved as working spec; IDs are stable. Change IDs only with an ADR.

Companion docs: [method.md](method.md), [architecture.md](architecture.md), [traceability.md](traceability.md), [abi.md](abi.md).

## 1. Purpose and scenario

mrdpd is a native RDP **server** for macOS. A standards-compliant RDP client (primary: Windows App on iPad; secondary: Windows App on macOS/Windows, FreeRDP) connects to the Mac and sees and controls the logged-in user's console session.

Primary scenario: full control of the Mac from an iPad over LAN or tunneled WAN (Tailscale/SSH), including the repair-window / lid-closed / headless case.

Secondary scenario: desktop-class clients (Mac/Windows) using multi-monitor, high-fidelity sessions.

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
- **C-HEADLESS** IronRDP headless — CI handshake, BMP, scripted input.

## 4. Features (stable IDs)

Each ID: protocol, macOS approach, engine status, tier, milestone.

### 4.1 Connection, security, session

| ID | Requirement | Protocol / API | Engine | Tier | Milestone |
| --- | --- | --- | --- | --- | --- |
| T1-SEC-01 | TLS 1.2/1.3 Enhanced RDP Security. First-run self-signed cert; optional cert paths in config | MS-RDPBCGR | built-in | T1 | M1 |
| T1-SEC-02 | NLA (CredSSP / NTLMv2). Credentials from mrdpd store, **not** the macOS login password | CredSSP, sspi-rs | `with_hybrid` | T1 | M1 |
| T1-SEC-03 | Single console session: mirror of the logged-in user. Max one **active** client | session | n/a | T1 | M1 |
| T1-SEC-04 | Bind-address policy: default localhost + explicit allowlist (or Tailscale iface). Port configurable (3389) | config | listen | T1 | M1 / M12 |
| T1-SEC-05 | Rate limit + lockout on failed auth | local | app | T1 | M12 |
| T1-SEC-06 | No plaintext RDP in release builds | build flag | n/a | T1 | M12 |
| T1-SEC-07 | Secrets in Keychain; config holds references | Keychain | n/a | T1 | M12 |
| T1-SEC-08 | Audit log: who / when / from-where / auth outcome | local | callbacks | T1 | M12 |
| T2-SEC-01 | Auto-reconnect cookies without re-auth loops | MS-RDPBCGR | **spike R5** | T2 | M1 spike; feature TBD |
| T2-SEC-02 | Network autodetect / RTT feeds encoder | autodetect, echo | built-in TBD | T2 | M10 |
| T2-SEC-03 | Optional read-only second viewer | session | TBD | T2 | optional after M6 |

### 4.2 Graphics

| ID | Requirement | Protocol / API | Engine | Tier | Milestone |
| --- | --- | --- | --- | --- | --- |
| T1-GFX-01 | Push BGRA frames with stride + dirty rects into the engine | ABI v1 | consume frames | T1 | M0–M2 |
| T1-GFX-02 | RDP 6.0 bitmap + interleaved RLE fallback | MS-RDPBCGR | built-in | T1 | M2 |
| T1-GFX-03 | RemoteFX (incl. progressive) default codec pre-EGFX | RemoteFX | built-in | T1 | M2 / M5 |
| T1-GFX-04 | Damage-driven encode, frame pacing (cap 60, adaptive) | SCK dirty + pacer | n/a | T1 | M5 |
| T1-GFX-05 | Cursor composited into frames | SCK cursor | n/a | T1 | M5 |
| T2-GFX-01 | Color pointer PDUs; client-side cursor | pointer PDUs | TBD | T2 | after M6 |
| T2-GFX-02 | EGFX H.264 AVC420 via VideoToolbox → `push_avc_frame` | MS-RDPEGFX | experimental **R4** | T2 | M10 |
| T2-GFX-03 | AVC444 after AVC420 is stable | MS-RDPEGFX | experimental | T2 | M10+ |

### 4.3 Display topology

RDP virtual desktop: primary at (0,0); others relative; negative origins allowed.

| ID | Requirement | Protocol / API | Engine | Tier | Milestone |
| --- | --- | --- | --- | --- | --- |
| T1-MON-01 | Single-monitor dynamic resize (client rotation / RDPEDISP one monitor) | MS-RDPEDISP | implemented | T1 | M8 |
| T2-MON-01 | Static multimon at connect (GCC monitor list) | GCC | **spike R1** | T2 | M9 |
| T2-MON-02 | Dynamic add/remove/rearrange | MS-RDPEDISP | implemented | T2 | M9 |
| T2-MON-03 | One SCStream per SCDisplay; dirty rects translated into virtual-desktop space; Retina consistent | SCK | n/a | T2 | M9 |
| T2-MON-04 | Virtual displays when client wants more monitors than exist / lid closed (`CGVirtualDisplay`, flag); HDMI dummy plug documented fallback | private API **R3** | n/a | T2 | M9 |

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
| T2-IN-03 | MS-RDPEI touch → gestures (two-finger scroll min; pinch best-effort) | MS-RDPEI | **spike R2** | T2 | after spike |
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

See [risks.md](risks.md). R1, R2, R5 are M1 DoD. R3 accepted as flag+dummy-plug. R4 accepted as RemoteFX fallback + engine swap.
