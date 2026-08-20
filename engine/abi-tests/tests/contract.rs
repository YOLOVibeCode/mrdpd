//! Compiles and runs `contract.c` against the StubEngine cdylib.

use std::path::{Path, PathBuf};
use std::process::Command;

fn profile_dir() -> &'static str {
    if cfg!(debug_assertions) {
        "debug"
    } else {
        "release"
    }
}

fn stub_dylib() -> PathBuf {
    let abi_tests = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let engine = abi_tests.parent().expect("engine/abi-tests");
    let name = "libmrdpd_stub_engine.dylib";
    let profile = profile_dir();
    let candidates = [
        engine.join("target").join(profile).join(name),
        engine.join("target").join(profile).join("deps").join(name),
    ];
    for path in &candidates {
        if path.exists() {
            return path.canonicalize().unwrap_or_else(|_| path.clone());
        }
    }
    panic!("StubEngine cdylib not found. Tried {candidates:?}");
}

fn clang_out() -> PathBuf {
    let abi_tests = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let engine = abi_tests.parent().expect("engine/abi-tests");
    engine
        .join("target")
        .join(profile_dir())
        .join("mrdpd-abi-contract")
}

#[test]
fn c_abi_contract_on_stub_engine() {
    // Pull in the stub crate so cargo builds the cdylib before dlopen.
    assert_eq!(mrdpd_stub_engine::mrdpd_engine_abi_version(), 1);

    let dylib = stub_dylib();
    let abi_tests = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let engine = abi_tests.parent().expect("engine/abi-tests");
    let repo = engine.parent().expect("repo root");
    let include = repo.join("include");
    let contract = abi_tests.join("contract.c");
    let runner = clang_out();
    if let Some(parent) = runner.parent() {
        std::fs::create_dir_all(parent).unwrap();
    }

    let compile = Command::new("clang")
        .args(["-std=c11", "-Wall", "-Wextra", "-Werror", "-O0", "-g"])
        .arg("-I")
        .arg(&include)
        .arg(&contract)
        .arg("-o")
        .arg(&runner)
        .status()
        .expect("failed to spawn clang");
    assert!(
        compile.success(),
        "clang failed to build {}",
        contract.display()
    );

    let run = Command::new(&runner)
        .arg(&dylib)
        .current_dir(repo)
        .status()
        .expect("failed to spawn ABI contract runner");
    assert!(
        run.success(),
        "ABI contract suite failed against {}",
        Path::new(&dylib).display()
    );
}
