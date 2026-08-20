# S4 recipes: Swift contracts + StubEngine ABI tests. No IronRDP.

stub-engine:
    cargo build --manifest-path engine/Cargo.toml -p mrdpd-stub-engine

test-abi: stub-engine
    cargo test --manifest-path engine/Cargo.toml

test-swift: stub-engine
    swift test

test: test-abi test-swift

test-frame:
    swift test --filter FrameKit

test-input:
    swift test --filter InputKit

test-engine: stub-engine
    swift test --filter EngineKit

check-secrets:
    bash scripts/check-secrets.sh --all
