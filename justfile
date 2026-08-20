# S4 owns richer recipes. S0 only needs these.

test:
    swift test
    cargo test --manifest-path engine/Cargo.toml

test-frame:
    swift test --filter FrameKit

test-input:
    swift test --filter InputKit

check-secrets:
    bash scripts/check-secrets.sh --all
