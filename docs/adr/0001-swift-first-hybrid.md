# ADR 0001: Swift-first hybrid with IronRDP engine

Status: accepted  
Date: 2026-08-20

## Context

We need a real RDP **server** on macOS so Windows App on iPad can drive the console session. Options considered:

1. Pure Rust (objc2 bindings to ScreenCaptureKit, CGEvent, pasteboard).
2. Swift application + IronRDP behind a C ABI.
3. Swift from scratch implementing MS-RDPBCGR and friends.
4. Revive FreeRDP’s abandoned macOS shadow server.

FreeRDP maintainers state there never was a working Mac server; Sequoia obsolete APIs; Homebrew disables it. From-scratch RDP in Swift is a multi-year codec and NLA project. Pure Rust pays an ongoing objc2 tax on every Apple API we actually care about.

IronRDP (`ironrdp-server`) is actively released, Apache-2.0, and already has TLS, NLA, RemoteFX, clipboard/audio/display-control crates, and experimental EGFX. It also ships a headless client we can use as an E2E harness.

## Decision

Swift owns the app, capture, input, clipboard, audio, VideoToolbox, TCC, and launchd. IronRDP is a **protocol engine** loaded as a dylib. Approximately all novel product code is Swift.

## Consequences

- Two toolchains (SwiftPM + Cargo). Daily Swift work uses a prebuilt dylib after M1.
- FFI lifetime/threading becomes a first-class test surface (`docs/abi.md`).
- Engine can be replaced (FreeRDP, or a future Swift stack) without rewriting macOS code.
- We depend on IronRDP’s experimental EGFX; RemoteFX remains the T1 path (ADR-adjacent to R4).
