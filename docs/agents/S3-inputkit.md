# Stream S3 — InputKit

Branch: `s3-inputkit`

## Goal

Pure Swift `InputEvent` and ISP protocol `InputSink` with `RecordingInputSink`. No CGEvent. No engine.

## Owns

- `Sources/InputKit/**`
- `Tests/InputKitTests/**`
- Traceability test path for `T1-IN-01`

## Must not touch

- `engine/**`, `include/**`
- `Sources/FrameKit/**`, `Sources/EngineKit/**`
- Keymap tables beyond what T1-IN-01 needs (full US map is M3 / later stream S6)

## TDD order

1. `InputEvent` key/mouse equality (no protocol yet)
2. Protocol `InputSink` with `handle(_: InputEvent)` only
3. `RecordingInputSink` passes `testInputSinkContract(_:)`
4. Do not add clipboard, gestures, or unicode IME

## Done when

`swift test --filter InputKit` is green and does not link the engine.

## Read first

`docs/modules.md`, `docs/spec.md` T1-IN-01, `docs/method.md`, `AGENTS.md`
