# M6: CGEventInputSink + live serve. `just test` TCC-free; capture/inject is `just test-local` / `just serve`.

stub-engine:
    cargo build --manifest-path engine/Cargo.toml -p mrdpd-stub-engine

engine:
    cargo build --manifest-path engine/Cargo.toml -p mrdpd-engine --features test-hooks

test-abi: stub-engine engine
    cargo test --manifest-path engine/Cargo.toml -p mrdpd-abi-tests

test-e2e: engine
    cargo test --manifest-path engine/Cargo.toml -p mrdpd-engine --tests --bins --lib

# Lab: 1080p quadrants (M2). Default 127.0.0.1:3390. Never 0.0.0.0.
serve-pattern host="127.0.0.1" port="3390":
    cargo run --manifest-path engine/Cargo.toml -p mrdpd-engine --bin mrdpd-pattern -- {{host}} {{port}}

# Lab: live desktop + injected input (M6). Needs Screen Recording and Accessibility. Never 0.0.0.0.
serve host="127.0.0.1" port="3390": engine
    swift run mrdpd-serve -- {{host}} {{port}}

# Manual second stack (T1-GFX-01). Requires `brew install freerdp`. Not part of `just test`.
test-freerdp:
    cargo test --manifest-path engine/Cargo.toml -p mrdpd-engine --test pattern_serve t1_gfx_01_freerdp -- --ignored --nocapture

# T1-IN-04: FastPath mouse against a running `just serve`. Not part of `just test`.
test-inject:
    cargo test --manifest-path engine/Cargo.toml -p mrdpd-engine --test serve_inject -- --ignored --nocapture

test-swift: stub-engine
    swift test

test: test-abi test-e2e test-swift

test-frame:
    swift test --filter FrameKit

# Screen Recording + Accessibility TCC. Fails if a required grant is missing. Not part of `just test`.
test-local:
    MRDPD_TEST_LOCAL=1 swift test --filter 'SCKFrameSource|CGEventInputSink'

# T1-PERF-01 pacer (TCC-free). T1-PERF-02/03/04 are live; see docs/bench.md.
bench:
    swift test --filter FramePacerTests

test-input:
    swift test --filter InputKit

test-engine: stub-engine
    swift test --filter EngineKit

check-secrets:
    bash scripts/check-secrets.sh --all

# Live loop (T1-IN-03/04, T1-PERF-02/03/04): probe window + mrdpd-serve + headless client,
# asserting on the HID event the Mac got and the pixels the client saw. Release builds so
# the perf numbers are honest. Needs Screen Recording + Accessibility; takes over the first
# display for ~1 min (Escape quits the probe). Not part of `just test`. See docs/live-check.md.
live-check filter="":
    cargo build --release --manifest-path engine/Cargo.toml -p mrdpd-engine
    swift build -c release --product mrdpd-serve
    swift build -c release --product mrdpd-probe
    MRDP_ENGINE_DYLIB="$PWD/engine/target/release/libmrdpd_engine.dylib" MRDPD_BIN_DIR="$PWD/.build/release" \
        cargo test --release --manifest-path engine/Cargo.toml -p mrdpd-engine --test live_check -- --ignored --test-threads=1 --nocapture {{filter}}
