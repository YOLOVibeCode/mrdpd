# Risks and spikes

Status values: `open` | `spiking` | `mitigated` | `accepted`.

| ID | Risk | Impact | Mitigation | Spike milestone | Status |
| --- | --- | --- | --- | --- | --- |
| R1 | IronRDP server-side static multimon (GCC monitor data) incomplete | M9 blocked or needs upstream PR | Spike in M1; dynamic RDPEDISP path is believed implemented; budget upstream PR | M1 | open |
| R2 | MS-RDPEI (touch) server support missing in IronRDP | iPad gestures T2 incomplete | Spike M1; two-finger scroll may be synthesized from mouse wheel as T1 fallback | M1 | open |
| R3 | `CGVirtualDisplay` is private | Headless / extra virtual monitors may break on OS upgrade | Feature flag; HDMI dummy plug is the supported fallback; no App Store | M9 | accepted (strategy) |
| R4 | EGFX / H.264 experimental in IronRDP | WAN quality | RemoteFX T1 path remains; ABI lets us swap engines | M10 | open |
| R5 | Reconnect cookies unverified in engine | Dropped Wi-Fi forces full re-auth | Spike M1; if missing, document reconnect as OUT until upstream | M1 | open |
| R6 | FFI buffer lifetime / callback threads | Heisenbugs, crashes in Windows App | Poison-after-return + thread-identity contract tests from M0 | M0 | open |
| R7 | StubEngine drifts from real engine | Swift tests lie | Same ABI suite on both dylibs; no stub-only shortcuts in the shared suite | M0–M1 | open |
| R8 | TCC cannot be granted in CI | Capture/inject untested in CI | `just test-local`; contract tests use synthetic/recording doubles in CI | ongoing | mitigated |
| R9 | FileVault pre-boot has no network | Repair-shop / reboot lockout | Document as OUT-03; dummy plug does not help pre-boot | — | accepted |
| R10 | Windows App iOS is strict and single-monitor | Multimon untestable on primary client | T1 gated on iPad; T2 multimon gated on macOS/Windows Windows App | ongoing | accepted |
| R11 | Two toolchains (SwiftPM + Cargo) | CI / local friction | `just` recipes; prebuilt engine dylib for daily Swift work after M1 | M0 | open |
| R12 | Keymap long tail (dead keys, non-US) | Wrong characters | Pure-data tables, unit tests per layout; US complete at M3, others incremental | M3+ | open |
| R13 | Private API + notarization of a dylib | Distribution pain | Sign both binaries; virtual display stays flag-off in release if it blocks notarization | M12 | open |
| R14 | Scope creep into T3 device redirection | Project never reaches M6 | AGENTS.md forbids T3; M6 survival gate | ongoing | mitigated |

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

Spikes are not optional color. R1/R2/R5 are M1 DoD.
