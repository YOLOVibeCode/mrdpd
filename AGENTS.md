# AGENTS.md

Rules for every human and every agent working in this repository. Read this file, `docs/method.md`, `docs/spec.md`, and `docs/traceability.md` before writing code.

## Memory

- The repo is memory. Chat is not.
- Any decision, spike finding, scope change, or “we agreed to…” must land in a markdown file in the same session: an ADR, `docs/risks.md`, `docs/spikes/`, or `docs/traceability.md`.
- Do not invent requirement IDs in code comments that do not exist in `docs/spec.md`.

## Method

- **TDD.** No production code without a failing test that cites a requirement ID (for example `T1-GFX-01`).
- **ISP.** A protocol or C header function exists only because a test needs it. Do not add methods “for later milestones.”
- **Constituents first.** Value types → segregated protocol + stub → contract suite on the stub → one real implementation → same suite on the real thing → wire two modules → E2E → interop.
- **Same suite, two implementations.** Stubs and real implementations pass identical contract tests. If the stub is allowed to cheat, the boundary has already drifted.

## Scope

- Implement T1 + T2 only. T3 and `OUT-*` are not work.
- **M6 is the survival gate** (live screen + injected input from iPad). Do not start T2 feature work (multimon, EGFX, audio, file clipboard) until M6 is interop-green, unless a T2 item is required to unblock a T1 bug.
- Rolling-wave tasks: `docs/tasks/m1.md`–`m6.md` (`m2`/`m5`/`m6` iPad deferred). Do not write novel task lists for M7+ until the previous gate is green.

## Boundaries

- The C ABI in `include/mrdpd_engine.h` is generated from `docs/abi.md`, not the other way around. Semantic changes go to `docs/abi.md` first, then the header, then tests, then code.
- Swift owns ScreenCaptureKit, CGEvent, NSPasteboard, VideoToolbox, CoreAudio, launchd, TCC.
- Rust/IronRDP is an engine behind the C ABI. Do not leak IronRDP types into Swift.

## Tests and CI

- `just test` must stay green and TCC-free.
- Capture and injection tests run as `just test-local` and are skipped in CI.
- Update `docs/traceability.md` in the same change as the test that covers an ID.
- A milestone is not done until `docs/dod.md` is checked off.

## Parallel agents

Multiple agents are allowed only as defined in [docs/workstreams.md](docs/workstreams.md). Each agent gets one stream file from [docs/agents/](docs/agents/). **Read-only** on everyone else’s tree. Shared files (`Package.swift`, `docs/abi.md`, `include/mrdpd_engine.h`) have a single owner per wave. Integration is stream S4, not a side effect of S1–S3.

## Do not

- Do not grant or simulate TCC permissions in CI.
- Do not fight FileVault pre-boot. Document it.
- Do not pre-create `ClipboardBridge`, `AudioSource`, or `AvcFrameSink` before their first failing test (M7 / M11 / M10).
- Do not edit another stream’s files “to be helpful.”
