# Stream S2 — FrameKit

Branch: `s2-framekit`

## Goal

Pure Swift value type `Frame` and ISP protocol `FrameSource` with `SyntheticFrameSource`. No capture. No engine.

## Owns

- `Sources/FrameKit/**`
- `Tests/FrameKitTests/**`
- Traceability test path for `T1-GFX-01` (synthetic frame only)

## Must not touch

- `engine/**`, `include/**`
- `Sources/InputKit/**`, `Sources/EngineKit/**`
- ScreenCaptureKit

## TDD order

1. `Frame` 2×2 BGRA, stride, dirty rect default = full frame (no protocol yet)
2. Protocol `FrameSource` — only what Synthetic needs (`frames` async sequence or `nextFrame()`)
3. `SyntheticFrameSource` passes the **contract suite** `testFrameSourceContract(_:)`
4. Do not add encode, audio, monitor list, or H.264 methods

## Done when

`swift test --filter FrameKit` (or `just test-frame`) is green and does not link the engine.

## Read first

`docs/modules.md` Always table, `docs/method.md`, `docs/spec.md` T1-GFX-01, `AGENTS.md`
