# Stream S2 — FrameKit

Branch: `s2-framekit`

## Goal

`Frame`, ISP `FrameSource` (`nextFrame()` only), `SyntheticFrameSource`, and M4 `SCKFrameSource`. No engine.

## Owns

- `Sources/FrameKit/**`
- `Tests/FrameKitTests/**`
- Traceability for `T1-GFX-01` (synthetic + SCK) and dirty-list `T1-GFX-04`

## Must not touch

- `engine/**`, `include/**`
- `Sources/InputKit/**`, `Sources/EngineKit/**`

## TDD order

1. `Frame` 2×2 BGRA, stride, dirty rect default = full frame (no protocol yet)
2. Protocol `FrameSource` — only `nextFrame()`
3. `SyntheticFrameSource` passes `testFrameSourceContract(_:)`
4. M4: `DirtyRects` + `CaptureFrame` (TCC-free), then `SCKFrameSource` (`just test-local`)
5. M5: `FramePacer`, `SCKSettings.showsCursor` (still not a `FrameSource` method)

## Done when

`swift test --filter FrameKit` is green without TCC. `just test-local` is green with Screen Recording.

## Read first

`docs/modules.md`, `docs/method.md`, `docs/spec.md` T1-GFX-01, `docs/tcc.md`, `AGENTS.md`
