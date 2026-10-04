# Risks and spikes

Status values: `open` | `spiking` | `mitigated` | `accepted`.

| ID | Risk | Impact | Mitigation | Spike milestone | Status |
| --- | --- | --- | --- | --- | --- |
| R1 | IronRDP server-side static multimon (GCC monitor data) incomplete | M9 blocked or needs upstream PR | [Spike](spikes/2026-08-20-r1-static-multimon.md): acceptor emits one primary monitor; RDPEDISP exists. T2-MON-01 = upstream/acceptor patch at M9, not OUT | M1 | mitigated |
| R2 | MS-RDPEI (touch) server support missing in IronRDP | iPad gestures T2 incomplete | [Spike](spikes/2026-08-20-r2-rdpei.md): `RdpeiServer` exists, `ironrdp-server` does not attach it. T2-IN-03 = upstream PR; T1 fallback = mouse wheel | M1 | mitigated |
| R3 | `CGVirtualDisplay` is private | Headless / extra virtual monitors may break on OS upgrade | Feature flag; HDMI dummy plug is the supported fallback; no App Store. macOS 26 surface is an Obj-C class (macrdp, [R16](spikes/2026-10-04-r16-clients-and-prior-art.md)) | M9 | accepted (strategy) |
| R4 | EGFX / H.264 experimental in IronRDP | WAN quality; 4K viewports | `ironrdp-egfx` 0.3 ships AVC420/AVC444 server and macrdp runs it in production ([R16](spikes/2026-10-04-r16-clients-and-prior-art.md)); RemoteFX stays the fallback; H.264 is T1 at V4 ([ADR 0007](adr/0007-h264-encode-scheduler.md)) | V4 | mitigated |
| R5 | Reconnect cookies unverified in engine | Dropped Wi-Fi forces full re-auth | [Spike](spikes/2026-08-20-r5-reconnect-cookies.md): API is on IronRDP **master**, not crates.io 0.13.0. M1 leaves cookies off; T2-SEC-01 after M6 on a newer crate. Not OUT | M1 | mitigated |
| R6 | FFI buffer lifetime / callback threads | Heisenbugs, crashes in Windows App | Poison-after-return + thread-identity contract tests on StubEngine **and** `mrdpd-engine` (`test-hooks`) | M0–M1 | mitigated |
| R7 | StubEngine drifts from real engine | Swift tests lie | Same ABI suite: `engine/abi-tests/tests/contract.rs` + `contract_engine.rs` (`--allow-missing-stub-hooks` only for stub-only mouse script) | M0–M1 | mitigated |
| R8 | TCC cannot be granted in CI | Capture/inject untested in CI | `just test-local`; contract tests use synthetic/recording doubles in CI | ongoing | mitigated |
| R9 | FileVault pre-boot has no network | Repair-shop / reboot lockout | Document as OUT-03; dummy plug does not help pre-boot | — | accepted |
| R10 | Windows App iOS is strict and single-monitor | Multimon untestable on primary client; iPad + 4K cannot be one session | Viewports ([ADR 0006](adr/0006-viewports.md)): one session per client screen; T2 desktop multimon gated on macOS/Windows Windows App | ongoing | accepted |
| R11 | Two toolchains (SwiftPM + Cargo) | CI / local friction | `just` recipes; prebuilt engine dylib for daily Swift work after M1 | M0 | open |
| R12 | Keymap long tail (dead keys, non-US) | Wrong characters | Pure-data tables, unit tests per layout; US complete at M3, others incremental | M3+ | open |
| R13 | Private API + notarization of a dylib | Distribution pain | Sign both binaries; virtual display stays flag-off in release if it blocks notarization | M12 | open |
| R14 | Scope creep into T3 device redirection | Project never reaches M6 | AGENTS.md forbids T3; M6 survival gate | ongoing | mitigated |

| R15 | Hardware encode budget: one engine cannot do 4K at 60 fps; two full-motion viewports exceed two engines | 4K viewport stutters or lags | [Spike R15](spikes/2026-10-04-r15-encode-budget.md); `EncodeScheduler` focus policy + tiling ([ADR 0007](adr/0007-h264-encode-scheduler.md)); measured fit 24/19/14 ms | V4 | open |
| R16 | Windows App on iPadOS unknowns: two windows at once, AVC420 decode, Cmd remapped to Ctrl, hotkey passthrough | Second screen or Mac shortcuts may not work with Windows App | [Spike R16](spikes/2026-10-04-r16-clients-and-prior-art.md); V0 device checklist ([tasks/v0.md](tasks/v0.md)); native client ([ADR 0008](adr/0008-native-ipad-client.md)) | V0 | open |
| R17 | Windows App on iPadOS may not render two EGFX surfaces on one output (needed for RDP tiling) | 4K60 over RDP not reachable | Fallback: focused 4K at 3008×1692 or 2560×1440 upscaled by the client, or 4K at 30 fps | V4 | open |
| R18 | `CGEventPost` does not trigger WindowServer symbolic hotkeys (Cmd+Tab, Cmd+`, Spotlight, screenshots) | "Full control" feels broken for app switching | Port macrdp's Accessibility-driven workarounds with tests ([ADR 0009](adr/0009-reuse-not-fork.md)) | V2 | open |
| R19 | Virtual displays are 1:1 on macOS 26 (HiDPI cannot be enabled) | A virtual "4K" screen is tiny UI or soft | Default to scaled physical HiDPI displays; HDMI dummy plug with HiDPI modes for crisp headless; virtual displays stay a flag | V1+ | accepted |
| R20 | Native client needs an Apple Developer account and distribution (TestFlight/ad hoc) | V5 blocked or 7-day reinstall loop | Owner accepted ADR 0008; team N42FM5L5KD (paid) signs `just ipad-device`. No Apple Development cert for that team on the lab Mac yet: Xcode creates it on first device install | V5 | mitigated |
| R22 | iPadOS reserves some shortcuts (Cmd+Tab, Cmd+Space, Globe) for itself | Those never reach the Mac from the iPad app | Documented in `docs/ipad.md`; Ctrl+Option switching avoids reserved combos | V5 | accepted |
| R23 | The host is an unsigned dev binary: TCC grants attach to the launching terminal, and pairing keys live in a 0600 file instead of the Keychain | Setup friction; key-at-rest weaker than Keychain | Signed host app + Keychain at M12 (T1-SEC-07, T1-OPS-04) | M12 | open |
| R21 | Prior art moves fast (macrdp ships weekly; IronRDP releases) | We re-implement what already exists, or miss upstream fixes | [ADR 0009](adr/0009-reuse-not-fork.md): port lessons with attribution; quarterly re-check of macrdp and IronRDP releases | ongoing | mitigated |

## Spike template (`docs/spikes/YYYY-MM-DD-rN-title.md`)

```markdown
# Spike RN: title

Date:
Question:
Build / version of IronRDP:
What we ran:
Evidence (logs, PDUs, links):
Answer:
Effect on spec / M9 / M10:
Follow-up (upstream issue, ADR, OUT-row):
```

Spikes are not optional color. R1/R2/R5 were M1 DoD and are written under `docs/spikes/`.
