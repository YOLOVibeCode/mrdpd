//! Same ABI v1 suite against the real IronRDP engine (T1-GFX-01, T1-SEC-04).
//! Stub-only `mrdpd_stub_script_mouse` is optional (`--allow-missing-stub-hooks`).
//! `mrdpd_stub_copy_last_frame` is present because this test builds with `test-hooks`.

use std::path::Path;

#[test]
fn c_abi_contract_on_real_engine() {
    assert_eq!(mrdpd_engine::mrdpd_engine_abi_version(), 1);

    let dylib = mrdpd_abi_tests::find_dylib("mrdpd-engine", "libmrdpd_engine.dylib");
    let runner = mrdpd_abi_tests::compile_contract("mrdpd-abi-contract-engine");
    mrdpd_abi_tests::run_contract(
        &runner,
        Path::new(&dylib),
        &["--allow-missing-stub-hooks"],
    );
}
