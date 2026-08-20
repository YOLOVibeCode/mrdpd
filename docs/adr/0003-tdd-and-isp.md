# ADR 0003: TDD and ISP; grow protocols from tests

Status: accepted  
Date: 2026-08-20

## Context

A project of this size dies from fat facades (`Engine` that does frames, H.264, clipboard, audio, layout) and from implementation-first modules that cannot be tested until everything is wired.

We also cannot freeze every future Swift protocol in M0 without violating Interface Segregation: callers would depend on methods that do not exist yet.

## Decision

- No production code without a failing test that cites a spec ID.
- Protocols and ABI functions exist only when a test requires them.
- M0 extracts only ABI v1 + `FrameSource` + `InputSink`.
- Clipboard / AVC / audio protocols are created in M7 / M10 / M11 on their first failing test.
- Contract suites take `any Protocol` / any ABI dylib.
- Constituents (value types, tables, stubs) are proven before composition.

## Consequences

- Faster M0 (less speculative code).
- Traceability matrix lists future IDs as `untested` without implying types exist.
- Agents must refuse “just add this method for later.”
