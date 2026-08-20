# Stream S1 — C ABI + StubEngine

Branch: `s1-abi-stub`

## Goal

Implement ABI v1 from `docs/abi.md` behind StubEngine. No IronRDP. No Swift (except you may uncomment the `AbiTests` target in `Package.swift` if S0 left a placeholder).

## Owns

- `include/mrdpd_engine.h`
- `engine/**` (stub crate / dylib)
- `Tests/AbiTests/**` or `engine/tests/**`
- Traceability cells for tests you add (`T1-GFX-01` push path, `T1-SEC-04` bind)

## Must not touch

- `Sources/FrameKit/**`, `Sources/InputKit/**`, `Sources/EngineKit/**`
- `docs/abi.md` semantics (if the header cannot express the doc, stop and open a blocker note)

## TDD order (from `docs/tasks/m0.md`)

1. `mrdpd_engine_abi_version() == 1`
2. start / already-started / stop idempotent / start-stop-start
3. start on bound port → BIND
4. `push_frame` 2×2 BGRA; **poison-after-return**
5. `push_frame` before start → NOT_STARTED
6. Test-only scripted mouse callback via `mrdpd_engine_test.h` (not in production ABI)

## Done when

- Contract suite green on StubEngine
- Header matches `docs/abi.md` names and error codes
- No Swift types invented here

## Read first

`docs/abi.md`, `docs/tasks/m0.md` M0b steps 3–8, `AGENTS.md`
