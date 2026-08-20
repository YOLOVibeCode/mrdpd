# Traceability matrix

Status values: `untested` → `contract-green` → `e2e-green` → `interop-green`. Non-goals: `accepted-out`. T3: `backlog`.

Update this table in the same change as the test. Empty **Test** cells after a milestone starts are defects.

Legend for **Boundary**: B1 wire, B2 ABI, B3 FrameSource, B4 InputSink, B5 clipboard (M7+), B6 audio (M11+), APP app/config, DATA pure data.

| ID | Boundary | Contract test (path) | E2E | Interop | Milestone | Status |
| --- | --- | --- | --- | --- | --- | --- |
| T1-SEC-01 | B2 | planned `engine/abi-tests` TLS listen | M1 BMP handshake | C-HEADLESS | M1 | untested |
| T1-SEC-02 | B2 | planned NLA config | M1 | C-IPAD M2+ | M1 | untested |
| T1-SEC-03 | APP | planned single-client reject | M1 | — | M1 | untested |
| T1-SEC-04 | APP | `engine/abi-tests/contract.c` (B2 dummy listen / `MRDPD_ERR_BIND` on 127.0.0.1); APP allowlist M12 | M1 | — | M1/M12 | untested |
| T1-SEC-05 | APP | planned lockout unit | — | — | M12 | untested |
| T1-SEC-06 | APP | planned release build flag test | — | — | M12 | untested |
| T1-SEC-07 | APP | planned Keychain round-trip | — | — | M12 | untested |
| T1-SEC-08 | APP | planned log line parse | — | — | M12 | untested |
| T2-SEC-01 | B1 | spike R5 | TBD | TBD | M1 spike | untested |
| T2-SEC-02 | B1 | planned | M10 | — | M10 | untested |
| T2-SEC-03 | APP | backlog optional | — | — | after M6 | untested |
| T1-GFX-01 | B2/B3 | B2: `engine/abi-tests/contract.c` (`push_frame` / poison-after-return); B3: `Tests/FrameKitTests/FrameTests.swift`, `Tests/FrameKitTests/FrameSourceContract.swift` | M1 solid BMP | M2 C-IPAD | M0–M2 | untested |
| T1-GFX-02 | B1 | M2 codec | golden | C-IPAD M2 | M2 | untested |
| T1-GFX-03 | B1 | M2/M5 | live | C-IPAD M5 | M5 | untested |
| T1-GFX-04 | B3 | M4 dirty-rect | M5 | — | M5 | untested |
| T1-GFX-05 | B3 | M4/M5 cursor composite | M5 | C-IPAD | M5 | untested |
| T2-GFX-01 | B1 | after M6 | — | C-DESK | after M6 | untested |
| T2-GFX-02 | B2 v2 | M10 first AVC test extracts ABI | M10 | C-IPAD WAN | M10 | untested |
| T2-GFX-03 | B2 | after AVC420 | M10+ | — | M10+ | untested |
| T1-MON-01 | B2/B3 | M8 resize callback | M8 size | C-IPAD rotate | M8 | untested |
| T2-MON-01 | B1 | M9; depends R1 | per-monitor golden | C-DESK | M9 | untested |
| T2-MON-02 | B1 | M9 layout change | E2E rearrange | C-DESK | M9 | untested |
| T2-MON-03 | B3 | M9 compositing | goldens | — | M9 | untested |
| T2-MON-04 | APP | M9 flag + fallback doc | local | — | M9 | untested |
| T1-IN-01 | B2/B4 | B2: `engine/abi-tests/contract.c` (`mrdpd_stub_script_mouse`); B4: `Tests/InputKitTests/InputEventTests.swift`, `Tests/InputKitTests/InputSinkContractTests.swift`; M3 FastPath | M3 sequence | — | M0/M3 | untested |
| T1-IN-02 | DATA | M3 keymap tables | — | — | M3 | untested |
| T1-IN-03 | B4 | M3/M6 coords | M6 | C-IPAD | M6 | untested |
| T1-IN-04 | B4 | M6 CGEvent contract | loopback | C-IPAD M6 | M6 | untested |
| T2-IN-01 | B4 | after M6 | — | — | after M6 | untested |
| T2-IN-02 | B4 | after M6 | — | — | after M6 | untested |
| T2-IN-03 | B1 | spike R2 | — | C-IPAD | spike | untested |
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
| T1-PERF-01 | B3/B1 | `just bench` | — | note | M5 | untested |
| T1-PERF-02 | B4/B1 | `just bench` | — | note | M6 | untested |
| T1-PERF-03 | B1 | `just bench` | — | note | M5 | untested |
| T1-PERF-04 | APP | `just bench` | — | note | M5 | untested |
| T2-PERF-01 | B1 | M10 A/B | — | WAN note | M10 | untested |
| T2-PERF-02 | B1 | M9 | — | C-DESK | M9 | untested |
| T1-OPS-01 | APP | M12 | clean VM | — | M12 | untested |
| T1-OPS-02 | APP | M12 config parse | — | — | M12 | untested |
| T1-OPS-03 | APP | M4/M6 docs + local | — | human | M4/M6/M12 | untested |
| T1-OPS-04 | APP | M12 | — | — | M12 | untested |
| T1-OPS-05 | APP | M12 | clean VM | — | M12 | untested |

## Coverage invariants

- No T1 ID may remain `untested` after its milestone DoD is claimed.
- `contract-green` without a listed test path is invalid.
- B5/B6 rows must not gain Swift types before their first failing test (ISP).
