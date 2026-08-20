# Stream S4 — EngineKit (Wave 2)

Branch: `s4-enginekit`

**Do not start until S1, S2, and S3 are merged to `main` (or you rebase on all three).**

## Goal

Thin Swift wrapper that `dlopen`s StubEngine, pushes one `Frame` from `SyntheticFrameSource`, and delivers one scripted input into `RecordingInputSink`.

## Owns

- `Sources/EngineKit/**`
- `Tests/EngineKitTests/**`
- `justfile` test recipes
- Traceability: composition row for T1-GFX-01 + T1-IN-01 wiring

## Must not touch

- StubEngine internals (use the public C ABI only)
- FrameKit/InputKit **behavior** (you may import them)
- IronRDP, ScreenCaptureKit, CGEvent

## TDD order

1. Version check `mrdpd_engine_abi_version() == 1` or refuse to load
2. start/stop from Swift
3. Push 2×2 frame; poison-after-return still holds
4. Scripted callback hops onto a known executor and hits `RecordingInputSink`
5. `just test` = FrameKit + InputKit + AbiTests + EngineKitTests

## Done when

`docs/tasks/m0.md` M0b steps 11–12 are checked. M0 DoD extra boxes in `docs/dod.md` can be ticked.

## Read first

`docs/abi.md`, `docs/tasks/m0.md`, `docs/dod.md`, `AGENTS.md`
