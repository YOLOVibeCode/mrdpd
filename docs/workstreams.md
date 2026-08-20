# Parallel workstreams

How multiple agents work at once **without colliding**. If two streams list the same path, they are not parallel — they are a queue.

## Rules (binding)

1. An agent owns **only** the paths in its stream file under [agents/](agents/). It may **read** anything else. It may **not** edit another stream’s files.
2. Shared files (`Package.swift`, `justfile`, `docs/abi.md`, `include/mrdpd_engine.h`) have a **single owner** per wave. Other streams treat them as frozen APIs.
3. Integration is its own stream. Do not “just wire it” at the end of a constituent stream.
4. TDD still applies inside a stream. Parallelism does not excuse skipping a failing test.
5. One stream = one git branch = one PR. Branch name = stream id (`s1-abi-stub`, `s2-framekit`, …).
6. If you need a type from another stream that does not exist yet, **stop** and record a blocker in `docs/tasks/m0.md`. Do not invent a duplicate type.

## Why this splits cleanly

The first slice is three constituents that only meet at EngineKit:

```text
        Frame (S2)          InputEvent (S3)         C ABI + StubEngine (S1)
            │                      │                         │
            └──────────┬───────────┴─────────────────────────┘
                       │
                 EngineKit (S4)   ← starts only when S1+S2+S3 are green
```

S2 never imports S1. S3 never imports S1 or S2. S1 has no Swift. That is the whole trick.

## Waves

### Wave 0 — lock the skeleton (one agent, minutes)

Owner: whoever starts the repo. **Must finish before S1/S2/S3 launch.**

- Create empty exclusive directories + `Package.swift` / Cargo stubs with **no behavior**
- GitHub `YOLOVibeCode/mrdpd` public, LICENSE, `.gitignore`, secret hooks
- Freeze `docs/abi.md` v1 (already written — treat as law)

Prompt: [agents/S0-bootstrap.md](agents/S0-bootstrap.md)

### Wave 1 — three agents in parallel (M0b constituents)

| Stream | Owns | Does not touch | Gate |
| --- | --- | --- | --- |
| [S1](agents/S1-abi-stub.md) | `engine/`, `include/`, `Tests/AbiTests/` | anything Swift | ABI contract green on StubEngine |
| [S2](agents/S2-framekit.md) | `Sources/FrameKit/`, `Tests/FrameKitTests/` | engine, InputKit, EngineKit | Frame + FrameSource + SyntheticFrameSource |
| [S3](agents/S3-inputkit.md) | `Sources/InputKit/`, `Tests/InputKitTests/` | engine, FrameKit, EngineKit | InputEvent + InputSink + RecordingInputSink |

S1 may add **one** target name to `Package.swift` / `engine/Cargo.toml` only if S0 left a commented placeholder. Prefer filling the placeholder over rewriting the manifest.

### Wave 2 — one agent (M0b integration)

| Stream | Owns | Needs | Gate |
| --- | --- | --- | --- |
| [S4](agents/S4-enginekit.md) | `Sources/EngineKit/`, `Tests/EngineKitTests/`, `justfile` recipes | S1 dylib, S2 Frame, S3 InputEvent | StubEngine + synthetic frame + recorded callback |

### Wave 3 — after M0 DoD (M1 vs keymap, still parallel)

| Stream | Owns | Parallel with |
| --- | --- | --- |
| S5 IronRDP engine | `engine/mrdpd-engine/` | S6 keymap |
| S6 Keymap tables | `Sources/InputKit/Keymap/` (S3 owner must be done) | S5 |
| S7 GitHub/CI polish | `.github/` | S5/S6 if it does not change test sources |

**Not parallel with S5:** anything that changes `docs/abi.md` or `include/mrdpd_engine.h`. ABI freeze until M8/M10.

### Sequential after that (do not fake parallelism)

| After | Stream | Why serial |
| --- | --- | --- |
| S4 | M2 pattern through real engine | needs S5 |
| S2 green | M4 SCKFrameSource | same protocol, new impl, needs TCC |
| S3+S6 | M6 CGEventInputSink | same protocol + keymap |
| M4+S5 | M5 live view | wiring |
| **M6 interop-green** | M7+ T2 | survival gate |

## File lock table (Wave 1)

| Path | Owner |
| --- | --- |
| `docs/abi.md` | frozen (S0). S1 implements; does not rewrite semantics |
| `include/mrdpd_engine.h` | S1 |
| `engine/**` | S1 |
| `Sources/FrameKit/**`, `Tests/FrameKitTests/**` | S2 |
| `Sources/InputKit/**`, `Tests/InputKitTests/**` | S3 |
| `Sources/EngineKit/**` | **empty until S4** |
| `Package.swift` | S0 creates; S1/S2/S3 only uncomment their target if needed; S4 may add EngineKit target |
| `AGENTS.md`, `docs/**` | docs owners; coding agents add a traceability test-path cell only for IDs they covered |
| `.gitignore`, `LICENSE`, `.githooks`, `.github` | S0 / later S7 |

## How to launch (Cursor)

Open four chats. Paste the stream file as the **entire** first message, plus:

> Stay in this stream. Do not edit files outside the Owns list. Stop if blocked.

Do not give one agent two streams.

## Merge order

1. S0 (if not already on `main`)
2. S1, S2, S3 — any order; they must not conflict. If they conflict, someone violated the lock table.
3. S4
4. Tag `m0b-green` when `just test` is green
