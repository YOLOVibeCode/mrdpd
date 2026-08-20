# Stream S0 — Bootstrap (serial, first)

You are the **only** agent in this wave. Finish before anyone launches S1/S2/S3.

## Goal

Lock directory ownership and publish the public repo so three agents can work without merge fights.

## Owns (only these)

- `Package.swift`
- `engine/Cargo.toml` (workspace stub)
- `include/.gitkeep` or header placeholder **without** inventing ABI beyond `docs/abi.md`
- `Sources/FrameKit/.gitkeep`, `Sources/InputKit/.gitkeep`, `Sources/EngineKit/.gitkeep`
- `Tests/FrameKitTests/.gitkeep`, `Tests/InputKitTests/.gitkeep`, `Tests/EngineKitTests/.gitkeep`, `Tests/AbiTests/.gitkeep`
- `.gitignore`, `LICENSE`, `NOTICE`, `.githooks/`, `scripts/check-secrets.sh`, `.gitleaks.toml`, `.github/workflows/secret-scan.yml`, `.env.example`
- git + `gh repo create YOLOVibeCode/mrdpd --public`

## Do not

- Implement Frame, StubEngine, or EngineKit
- Change `docs/abi.md` semantics
- Start IronRDP

## Done when

- Empty modules exist and SwiftPM/Cargo **parse** (targets may have a one-line dummy if the toolchain requires a source file)
- Secret guard is in place (`core.hooksPath=.githooks`)
- `https://github.com/YOLOVibeCode/mrdpd` exists and is **public**
- `git ls-files` has no `.env`, `*.pem`, `*.key`

## Read first

`AGENTS.md`, `docs/abi.md`, `docs/workstreams.md`, `docs/tasks/m0.md`
