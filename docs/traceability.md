# Traceability matrix

Status values: `untested` → `contract-green` → `e2e-green` → `interop-green`. Non-goals: `accepted-out`. T3: `backlog`.

Update this table in the same change as the test. Empty **Test** cells after a milestone starts are defects.

Legend for **Boundary**: B1 wire, B2 ABI, B3 FrameSource, B4 InputSink, B5 clipboard (M7+), B6 audio (M11+), APP app/config, DATA pure data.

| ID | Boundary | Contract test (path) | E2E | Interop | Milestone | Status |
| --- | --- | --- | --- | --- | --- | --- |
| T1-SEC-01 | B2 | `engine/mrdpd-engine/tests/solid_color.rs` (TLS listen + handshake) | `solid_color.rs` BMP | C-HEADLESS | M1 | e2e-green |
| T1-SEC-02 | B2 | `solid_color.rs` CredSSP / NLA (`with_hybrid` + config username/password) | M1 handshake | C-IPAD M2+ | M1 | e2e-green |
| T1-SEC-03 | APP | sequential `RdpServer::run` in `engine/mrdpd-engine/src/lib.rs` (one `run_connection`; second peer waits — ADR 0004); one-client proof `solid_color.rs` | M1 one client | — | M1 | e2e-green |
| T1-SEC-04 | APP | `engine/abi-tests/contract.c` (B2 dummy listen / `MRDPD_ERR_BIND`); `mrdpd-pattern` and `BindHost` / `mrdpd-serve` refuse `0.0.0.0`/`::` (exit 4); E2E binds `127.0.0.1` only. APP allowlist remains M12 | M1/M2/M5 loopback | — | M1/M12 | e2e-green |
| T1-SEC-05 | APP | planned lockout unit | — | — | M12 | untested |
| T1-SEC-06 | APP | planned release build flag test | — | — | M12 | untested |
| T1-SEC-07 | APP | planned Keychain round-trip | — | — | M12 | untested |
| T1-SEC-08 | APP | planned log line parse | — | — | M12 | untested |
| T2-SEC-01 | B1 | spike [R5](spikes/2026-08-20-r5-reconnect-cookies.md): implement after M6 on an IronRDP with `with_auto_reconnect_cookie` (not crates.io 0.13.0) | TBD | C-IPAD / C-DESK | after M6 | untested |
| T2-SEC-02 | B1 | planned | M10 | — | M10 | untested |
| T2-SEC-03 | APP | backlog optional | — | — | after M6 | untested |
| T1-GFX-01 | B2/B3 | B2: `engine/abi-tests/contract.c` + `tests/contract_engine.rs`; B3: `Tests/FrameKitTests/*` (incl. 1080p quadrants + `SCKFrameSourceTests` via `just test-local`); composition: `Tests/EngineKitTests/EngineKitTests.swift` (`testPush1080pPatternSurvivesPoisonAfterReturn`, `testPacedPumpDropsSecondCallInsideInterval`); lab: `mrdpd-pattern` + `mrdpd-serve`; FreeRDP: `t1_gfx_01_freerdp_connects_to_pattern_bin` (`just test-freerdp`) + live GDI against `mrdpd-serve` | `solid_color.rs` #FF00FF; `pattern_1080.rs` + `mrdpd-pattern` 1920×1080 quadrants (RemoteFX, interior ±24); live: `just serve` 3360×1890 | M2 C-FREERDP pattern; M5 C-FREERDP live GDI BGRA32; C-IPAD deferred | M0–M5 | e2e-green |
| T1-GFX-02 | B1 | not exercised: IronRDP client advertises RemoteFX so the server never falls back to RDP 6 / RLE. See `pattern_1080.rs` header. No extra ABI to force RLE (ISP). | — | — | M2 | untested |
| T1-GFX-03 | B1 | `engine/mrdpd-engine/tests/pattern_1080.rs` (and M1 `solid_color.rs`): QoiZ compile-out; session decodes RemoteFX surface | 1080p quadrant BMP | C-IPAD live view deferred (no device); C-FREERDP pattern still M2 | M2 / M5 | e2e-green |
| T1-GFX-04 | B3 | Dirty list: `Tests/FrameKitTests/DirtyRectsTests.swift` + `SCKFrameSource` (`just test-local`). Pacer: `Tests/FrameKitTests/FramePacerTests.swift`. Pump: `EngineKitTests.testPacedPumpDropsSecondCallInsideInterval` | `just serve` live path | — | M4 / M5 | contract-green |
| T1-GFX-05 | B3 | `Tests/FrameKitTests/SCKSettingsTests.swift`; `SCKFrameSource.showsCursor` under `just test-local` | `just serve` | C-IPAD deferred | M5 | contract-green |
| T2-GFX-01 | B1 | after M6 | — | C-DESK | after M6 | untested |
| T2-GFX-02 | B2 v2 | M10 first AVC test extracts ABI | M10 | C-IPAD WAN | M10 | untested |
| T2-GFX-03 | B2 | after AVC420 | M10+ | — | M10+ | untested |
| T1-MON-01 | B2/B3 | M8 resize callback | M8 size | C-IPAD rotate | M8 | untested |
| T2-MON-01 | B1 | M9; [spike R1](spikes/2026-08-20-r1-static-multimon.md): upstream acceptor / patch (GCC `TS_UD_CS_MONITOR` → N monitors). Not OUT | per-monitor golden | C-DESK | M9 | untested |
| T2-MON-02 | B1 | M9 layout change | E2E rearrange | C-DESK | M9 | untested |
| T2-MON-03 | B3 | M9 compositing | goldens | — | M9 | untested |
| T2-MON-04 | APP | M9 flag + fallback doc | local | — | M9 | untested |
| T1-IN-01 | B2/B4 | B2: `engine/abi-tests/contract.c` (`mrdpd_stub_script_mouse`, `mrdpd_stub_script_key`); B4: `Tests/InputKitTests/*`; composition: `Tests/EngineKitTests/EngineKitTests.swift` (`testScriptedKeySequenceHopsToRecordingInputSink`) | `engine/mrdpd-engine/tests/input_sequence.rs` FastPath A down/up | — | M0/M3 | e2e-green |
| T1-IN-02 | DATA | `Tests/InputKitTests/UsKeymapTests.swift` (`Sources/InputKit/Keymap/UsKeymap.swift`) | — | — | M3 | contract-green |
| T1-IN-03 | B4 | `input_sequence.rs` move / left / vertical wheel in virtual-desktop pixels; Retina: `Tests/InputKitTests/DisplayMapTests.swift` + `InjectionPlanTests` | M3 FastPath; M6 `DisplayMap` | C-IPAD deferred | M3 / M6 | e2e-green |
| T1-IN-04 | B4 | `Tests/InputKitTests/InjectionPlanTests.swift`; `CGEventInputSinkTests.testMouseMovePostsWhenAccessibilityGranted` (`just test-local`); live: `engine/mrdpd-engine/tests/serve_inject.rs` (`just test-inject`) | FastPath mouse → HID on `just serve` | C-IPAD deferred | M6 | e2e-green |
| T2-IN-01 | B4 | after M6 | — | — | after M6 | untested |
| T2-IN-02 | B4 | after M6 | — | — | after M6 | untested |
| T2-IN-03 | B1 | [spike R2](spikes/2026-08-20-r2-rdpei.md): upstream PR to attach `RdpeiServer`; T1 fallback = mouse wheel. Not OUT | — | C-IPAD | after M6 | untested |
| OUT-IN-01 | — | — | — | — | — | accepted-out |
| T1-CLP-01 | B5 | M7 first test creates protocol | round-trip | C-IPAD | M7 | untested |
| T2-CLP-01 | B5 | M7+ | — | C-IPAD | M7+ | untested |
| T2-CLP-02 | B5 | M7+ | — | C-DESK | M7+ | untested |
| T2-AUD-01 | B6 | M11 first test creates protocol | tone | C-IPAD | M11 | untested |
| T3-AUD-01 | — | — | — | — | after M12 | backlog |
| T3-DEV-01 | — | — | — | — | after M12 | backlog |
| T3-DEV-02 | — | — | — | — | after M12 | backlog |
| OUT-DEV-01 | — | — | — | — | — | accepted-out |
| OUT-DEV-02 | — | — | — | — | — | accepted-out |
| OUT-01 | — | — | — | — | — | accepted-out |
| OUT-02 | — | — | — | — | — | accepted-out |
| OUT-03 | — | — | — | — | — | accepted-out |
| OUT-04 | — | — | — | — | — | accepted-out |
| OUT-05 | — | — | — | — | — | accepted-out |
| T1-PERF-01 | B3/B1 | `just bench` → `FramePacerTests.testAllowsAtLeast30FpsWhenClockAdvances` ([bench.md](bench.md)) | LAN fps in M5 interop log | note | M5 | contract-green |
| T1-PERF-02 | B4/B1 | skipped E2E `CGEventInputSinkTests.testPerf02InputToPhotonIsManualInterop`; measure on `just serve` ([bench.md](bench.md)) | — | note | M6 | untested |
| T1-PERF-03 | B1 | skipped E2E `EngineKitTests.testPerf03IdleBitrateIsManualInterop`; measure on `just serve` ([bench.md](bench.md)) | — | note | M5 | untested |
| T1-PERF-04 | APP | skipped E2E `EngineKitTests.testPerf04IdleCpuIsManualInterop`; measure on `just serve` ([bench.md](bench.md)) | — | note | M5 | untested |
| T2-PERF-01 | B1 | M10 A/B | — | WAN note | M10 | untested |
| T2-PERF-02 | B1 | M9 | — | C-DESK | M9 | untested |
| T1-OPS-01 | APP | M12 | clean VM | — | M12 | untested |
| T1-OPS-02 | APP | M12 config parse | — | — | M12 | untested |
| T1-OPS-03 | APP | `docs/tcc.md`; SCK + CGEvent tests skip unless `MRDPD_TEST_LOCAL=1`, fail if TCC missing; `mrdpd-serve` exits if Accessibility missing | — | human | M4/M6/M12 | contract-green |
| T1-OPS-04 | APP | M12 | — | — | M12 | untested |
| T1-OPS-05 | APP | M12 | clean VM | — | M12 | untested |

## Coverage invariants

- No T1 ID may remain `untested` after its milestone DoD is claimed.
- `contract-green` without a listed test path is invalid.
- B5/B6 rows must not gain Swift types before their first failing test (ISP).
