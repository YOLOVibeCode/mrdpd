# Method: TDD + ISP, constituents forward

## Why this method

RDP on macOS fails in the gaps: a capture module that almost matches what the engine expects, an FFI buffer the engine retains one frame too long, a keymap that works for letters and dies on Cmd. We do not discover those gaps at M12. We make each gap a failing test at the module that owns it.

## TDD loop

Every change, including the first line of Swift or Rust:

1. Write one failing test that names a single behavior and cites a requirement ID.
2. Write the smallest type that makes it pass (often a stub or a pure function).
3. Refactor only while green.
4. Do not write production code for a requirement that has no failing test.

Red means the test compiled and failed for the right reason. A test that does not compile is not red yet.

## ISP (Interface Segregation)

Clients depend on the smallest protocol they actually call.

- A protocol exists only when a test needs it.
- A protocol has only the methods the current caller uses.
- Split when a caller would otherwise take unused methods.
- Do **not** pre-create later-milestone protocols in M0.

Fat facades (`DesktopEngine` with capture + encode + clipboard + audio + layout) are forbidden. The C ABI is also segregated by version: v1 is start/stop/frame/input only.

## Constituents-forward order

Smallest thing that can be tested, then the next thing that composes it.

```text
pure data (Frame, InputEvent, keymap tables, rects)
  → segregated protocol + stub
    → contract suite against the stub
      → one real implementation behind that protocol
        → same suite against the real thing
          → wire two real modules
            → E2E harness (headless IronRDP client)
              → interop (Windows App, FreeRDP)
```

A later module may not be wired until every constituent it depends on is green in isolation.

Illegal example: M5 “live desktop” before `FrameSource` is green on both `SyntheticFrameSource` and `SCKFrameSource`.

Legal example: M3 keymap table as pure data with unit tests, feeding `RecordingInputSink`, before any CGEvent exists.

## Contract tests

A contract suite is a function of a protocol, not of a class:

- `func testFrameSourceContract(_ source: any FrameSource)`
- The C ABI runner loads **any** dylib that exports `mrdpd_engine.h` and runs the same cases against StubEngine and the real engine.

If StubEngine is given a shortcut the real engine cannot take, delete the shortcut. The stub’s job is to be a faithful, deterministic engine, not a convenient one.

## First slice (M0b) — the only interfaces that exist yet

See [architecture.md](architecture.md) and [modules.md](modules.md). M0b extracts:

- C ABI v1: version, start, stop, push_frame, input/connect/log callbacks
- Swift `FrameSource` + `SyntheticFrameSource`
- Swift `InputSink` + `RecordingInputSink`
- Swift `Engine` wrapper over the C ABI v1 surface

`ClipboardBridge`, `AudioSource`, and `AvcFrameSink` are rows in the spec and traceability matrix. They are not Swift types until M7 / M11 / M10 write their first failing test.

## Outside-in vs inside-out

Use both, never only one:

- **Outside-in** for a milestone gate: one E2E test that names the user-visible behavior (solid-color BMP, then live frame, then injected character).
- **Inside-out** for the constituents that E2E will need: keymap table, dirty-rect math, ABI lifetime, before they are wired.

The outside-in test stays red (or `@ignored` with a requirement ID) until the constituents make it pass. It is not deleted to keep CI green. Prefer a skipped E2E with a cited ID over a silent absence.
