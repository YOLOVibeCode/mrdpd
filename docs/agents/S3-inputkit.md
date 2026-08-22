# Stream S3 — InputKit

Branch: `s3-inputkit`

## Goal

`InputEvent`, ISP `InputSink` (`handle` only), `RecordingInputSink`, keymap, M6 `CGEventInputSink`. No engine.

## Owns

- `Sources/InputKit/**`
- `Tests/InputKitTests/**`
- Traceability test path for `T1-IN-01`

## Must not touch

- `engine/**`, `include/**`
- `Sources/FrameKit/**`, `Sources/EngineKit/**`

## TDD order

1. `InputEvent` key/mouse equality (no protocol yet)
2. Protocol `InputSink` with `handle(_: InputEvent)` only
3. `RecordingInputSink` passes `testInputSinkContract(_:)`
4. M3: pure-data US keymap in `Sources/InputKit/Keymap/` (T1-IN-02)
5. M6: `DisplayMap` + `InjectionPlan` (TCC-free); `CGEventInputSink` under `just test-local`

## Done when

`swift test --filter InputKit` is green and does not link the engine.

## Read first

`docs/modules.md`, `docs/spec.md` T1-IN-01 / T1-IN-02, `docs/method.md`, `AGENTS.md`

