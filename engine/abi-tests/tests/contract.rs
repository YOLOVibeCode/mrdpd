//! Compiles and runs `contract.c` against the StubEngine cdylib.

use std::path::Path;

#[test]
fn c_abi_contract_on_stub_engine() {
    // Pull in the stub crate so cargo builds the cdylib before dlopen.
    assert_eq!(mrdpd_stub_engine::mrdpd_engine_abi_version(), 1);

    let dylib = mrdpd_abi_tests::find_dylib("stub", "libmrdpd_stub_engine.dylib");
    let runner = mrdpd_abi_tests::compile_contract("mrdpd-abi-contract");
    mrdpd_abi_tests::run_contract(&runner, Path::new(&dylib), &[]);
}
