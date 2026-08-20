# ADR 0002: C ABI is the only engine interface

Status: accepted  
Date: 2026-08-20

## Context

Swift and IronRDP must meet. Candidates: UniFFI, CXX, hand-written C ABI, JSON over a socket.

We need: a stable, versioned, testable boundary; StubEngine without Rust in the Swift test loop; poison-after-return tests; a future FreeRDP dylib with the same symbols.

## Decision

A handwritten C ABI specified in `docs/abi.md` and declared in `include/mrdpd_engine.h`. Swift `EngineKit` `dlopen`s the dylib and checks `mrdpd_engine_abi_version()`.

UniFFI is not used for v1: we need explicit buffer-borrow semantics that are easy to test in C.

## Consequences

- Header and `abi.md` must stay in lockstep; abi.md wins on conflict.
- Additive features bump ABI version (clipboard, AVC, audio) rather than silently growing v1 structs.
- StubEngine and real engine pass the **same** C test runner.
- No IronRDP types in Swift. No AppKit types in Rust.
