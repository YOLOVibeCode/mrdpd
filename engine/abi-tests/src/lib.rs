//! Shared helpers for compiling `contract.c` against a cdylib.

use std::path::{Path, PathBuf};
use std::process::Command;

pub fn profile_dir() -> &'static str {
    if cfg!(debug_assertions) {
        "debug"
    } else {
        "release"
    }
}

pub fn engine_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("engine/")
        .to_path_buf()
}

pub fn repo_root() -> PathBuf {
    engine_root().parent().expect("repo").to_path_buf()
}

pub fn find_dylib(package_dir_name: &str, file_name: &str) -> PathBuf {
    let engine = engine_root();
    let profile = profile_dir();
    let candidates = [
        engine.join("target").join(profile).join(file_name),
        engine
            .join("target")
            .join(profile)
            .join("deps")
            .join(file_name),
        engine
            .join(package_dir_name)
            .join("target")
            .join(profile)
            .join(file_name),
    ];
    for path in &candidates {
        if path.exists() {
            return path.canonicalize().unwrap_or_else(|_| path.clone());
        }
    }
    panic!("{file_name} not found. Tried {candidates:?}");
}

pub fn compile_contract(runner_name: &str) -> PathBuf {
    let engine = engine_root();
    let repo = repo_root();
    let include = repo.join("include");
    let contract = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("contract.c");
    let runner = engine.join("target").join(profile_dir()).join(runner_name);
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
    runner
}

pub fn run_contract(runner: &Path, dylib: &Path, extra_args: &[&str]) {
    let mut cmd = Command::new(runner);
    cmd.arg(dylib);
    for arg in extra_args {
        cmd.arg(arg);
    }
    let run = cmd
        .current_dir(repo_root())
        .status()
        .expect("failed to spawn ABI contract runner");
    assert!(
        run.success(),
        "ABI contract suite failed against {}",
        dylib.display()
    );
}
