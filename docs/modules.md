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
| mrdpd-engine (IronRDP) | ABI v1 | T1-SEC-01/02, T1-GFX-02/03 |
| Headless harness | engine | T1-GFX-01 |
| Keymap tables | InputEvent | T1-IN-02 |
| SCKFrameSource | FrameSource | T1-GFX-04/05 |
| Dirty-rect / Retina mapper | Frame | T1-IN-03, T1-GFX-04 |
| CGEventInputSink | InputSink, keymap | T1-IN-04 |
| App session (one client) | EngineKit | T1-SEC-03 |

## Extract later (not types today)

| When | Protocol | First test |
| --- | --- | --- |
| M7 | `ClipboardBridge` | string round-trip T1-CLP-01 |
| M8 | layout callback on ABI v1+ or v2 | T1-MON-01 |
| M9 | `MonitorLayout` value type + compositor | T2-MON-03 |
| M10 | `AvcFrameSink` / `push_avc_frame` | T2-GFX-02 |
| M11 | `AudioSource` | T2-AUD-01 |
| M12 | config, Keychain, LaunchAgent | T1-OPS-* |

Resize (M8) may be an additive ABI function. That is a version bump per [abi.md](abi.md), not a method secretly added to `push_frame`.
