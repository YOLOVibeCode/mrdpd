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

# ViewportKit (native viewport protocol, transport, client) on macOS; TCC-free.
test-viewportkit:
    swift test --package-path Packages/ViewportKit

test: test-abi test-e2e test-swift test-viewportkit

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

# Encode budget (spike R15, ADR 0007): concurrent VideoToolbox H.264/HEVC viewports at 60 fps.
# Synthetic desktop-like frames, no TCC. ~2 min. Not part of `just test`.
bench-encode:
    mkdir -p .build/bench
    swiftc -O -swift-version 5 scripts/bench/encode-budget.swift -o .build/bench/encode-budget
    .build/bench/encode-budget

# --- Native iPad client (ADR 0008; docs/ipad.md) ---

# Mac side: serve the iPad app on an explicit address (Tailscale or LAN). Needs Screen Recording +
# Accessibility on this terminal. Never 0.0.0.0.
host-serve bind port="3399":
    swift build -c release --product mrdpd-host
    .build/release/mrdpd-host serve --bind {{bind}} --port {{port}}

# Pair an iPad: copies an mrdpd:// link to the clipboard and shows a QR code (secret; shown once).
host-pair bind port="3399" name="iPad":
    swift build -c release --product mrdpd-host
    .build/release/mrdpd-host pair --bind {{bind}} --port {{port}} --name "{{name}}"

# Generate apps/ipad/mrdpd-ipad.xcodeproj from project.yml (brew install xcodegen).
ipad-project:
    cd apps/ipad && xcodegen generate --spec project.yml --quiet

# Build the iPad app for the simulator (no signing).
ipad-build: ipad-project
    xcodebuild -project apps/ipad/mrdpd-ipad.xcodeproj -scheme mrdpd -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath .build/ipad CODE_SIGNING_ALLOWED=NO build -quiet

# The app in an iPad Pro 13" simulator against a real host on loopback; input logged, never posted.
ipad-sim-check: ipad-project
    swift build --product mrdpd-host
    ./scripts/ipad-sim-check.sh

# Build, sign (Automatic, your team), and install on the iPad connected by USB or Wi-Fi.
ipad-device team="N42FM5L5KD": ipad-project
    xcodebuild -project apps/ipad/mrdpd-ipad.xcodeproj -scheme mrdpd -configuration Release \
        -destination 'generic/platform=iOS' -derivedDataPath .build/ipad DEVELOPMENT_TEAM={{team}} \
        -allowProvisioningUpdates build -quiet
    xcrun devicectl list devices
    @echo "Install with: xcrun devicectl device install app --device <iPad name or id> .build/ipad/Build/Products/Release-iphoneos/mrdpd.app"
