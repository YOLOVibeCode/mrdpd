//! T1-GFX-01: the lab `mrdpd-pattern` binary serves 1080p quadrants on 127.0.0.1 (T1-SEC-04).
//! No new C ABI. FreeRDP/iPad attach to this process, not to `cargo test`.

mod common;

use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use mrdpd_engine::pattern::{HEIGHT, WIDTH};

const RFX_TOLERANCE: u8 = 24;

struct KillOnDrop(Child);

impl Drop for KillOnDrop {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn sample_rgba(rgba: &[u8], x: u32, y: u32) -> [u8; 4] {
    let i = ((y * WIDTH + x) * 4) as usize;
    [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]]
}

fn near(px: [u8; 4], rgb: [u8; 3], tol: u8) -> bool {
    px[0].abs_diff(rgb[0]) <= tol && px[1].abs_diff(rgb[1]) <= tol && px[2].abs_diff(rgb[2]) <= tol
}

fn quadrants_ready(rgba: &[u8]) -> bool {
    if rgba.len() != (WIDTH * HEIGHT * 4) as usize {
        return false;
    }
    near(sample_rgba(rgba, 480, 270), [0xFF, 0x00, 0x00], RFX_TOLERANCE)
        && near(sample_rgba(rgba, 1440, 270), [0x00, 0xFF, 0x00], RFX_TOLERANCE)
        && near(sample_rgba(rgba, 480, 810), [0x00, 0x00, 0xFF], RFX_TOLERANCE)
        && near(sample_rgba(rgba, 1440, 810), [0xFF, 0xFF, 0xFF], RFX_TOLERANCE)
}

fn spawn_pattern(port: u16) -> KillOnDrop {
    KillOnDrop(
        Command::new(env!("CARGO_BIN_EXE_mrdpd-pattern"))
            .args(["127.0.0.1", &port.to_string()])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn mrdpd-pattern"),
    )
}

fn wait_listening(child: &mut KillOnDrop) -> String {
    let stderr = child.0.stderr.take().expect("stderr");
    let (ready_tx, ready_rx) = std::sync::mpsc::sync_channel(1);
    std::thread::spawn(move || {
        let mut lines = BufReader::new(stderr).lines();
        for line in &mut lines {
            let Ok(line) = line else {
                break;
            };
            if line.contains("listening") {
                let _ = ready_tx.send(Some(line));
                return;
            }
        }
        let _ = ready_tx.send(None);
    });
    ready_rx
        .recv_timeout(Duration::from_secs(10))
        .expect("mrdpd-pattern start timed out")
        .expect("mrdpd-pattern did not print listening (T1-GFX-01 lab server)")
}

fn look_path(name: &str) -> Option<PathBuf> {
    let out = Command::new("/bin/sh")
        .args(["-lc", &format!("command -v {name}")])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let p = String::from_utf8_lossy(&out.stdout).trim().to_owned();
    if p.is_empty() {
        None
    } else {
        Some(PathBuf::from(p))
    }
}

#[test]
fn t1_sec_04_pattern_bin_rejects_unspecified_bind() {
    let out = Command::new(env!("CARGO_BIN_EXE_mrdpd-pattern"))
        .args(["0.0.0.0", "3390"])
        .output()
        .expect("spawn mrdpd-pattern");
    assert_eq!(out.status.code(), Some(4), "T1-SEC-04 exit");
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(err.contains("T1-SEC-04"), "stderr: {err}");
}

#[test]
fn t1_gfx_01_pattern_bin_serves_1080p_on_loopback() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("error")),
        )
        .with_test_writer()
        .try_init();

    let port = common::free_loopback_port();
    let mut child = spawn_pattern(port);
    let line = wait_listening(&mut child);
    assert!(
        line.contains("127.0.0.1"),
        "T1-SEC-04 loopback in ready line: {line}"
    );

    let host_s = "127.0.0.1".to_owned();
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    let _client = std::thread::Builder::new()
        .name("mrdpd-pattern-bin-client".into())
        .spawn(move || {
            let result = common::screenshot(
                &host_s,
                port,
                "mrdpd",
                "changeme",
                WIDTH as u16,
                HEIGHT as u16,
                Duration::from_secs(30),
                quadrants_ready,
            );
            let _ = tx.send(result);
        })
        .expect("client thread");
    let result = rx
        .recv_timeout(Duration::from_secs(45))
        .expect("headless client timed out against mrdpd-pattern");
    drop(child);
    let rgba = result.expect("screenshot from mrdpd-pattern");

    let out = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join("e2e-pattern-bin.bmp");
    if let Some(parent) = out.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = common::write_bmp_bgr(&out, WIDTH, HEIGHT, &rgba);

    assert!(
        quadrants_ready(&rgba),
        "T1-GFX-01 mrdpd-pattern quadrants (bmp {:?})",
        out
    );
}

/// T1-GFX-01 FreeRDP second stack. Not part of `just test` (needs Homebrew `freerdp`).
/// Run: `just test-freerdp`.
#[test]
#[ignore = "T1-GFX-01: Homebrew freerdp; just test-freerdp"]
fn t1_gfx_01_freerdp_connects_to_pattern_bin() {
    let client = look_path("sdl-freerdp")
        .or_else(|| look_path("sdl3-freerdp"))
        .or_else(|| look_path("xfreerdp"))
        .expect("T1-GFX-01: install FreeRDP (`brew install freerdp`)");

    let port = common::free_loopback_port();
    let mut server = spawn_pattern(port);
    let line = wait_listening(&mut server);
    assert!(line.contains("127.0.0.1"), "{line}");

    let log_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join("freerdp-client.log");
    if let Some(parent) = log_path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::remove_file(&log_path);
    // PTY so FreeRDP INFO (GDI) is line-buffered; a plain file swallows it until exit.
    let freerdp = KillOnDrop(
        Command::new("script")
            .args([
                "-q",
                log_path.to_str().unwrap(),
                client.to_str().unwrap(),
                "/v:127.0.0.1",
                &format!("/port:{port}"),
                "/u:mrdpd",
                "/p:changeme",
                "/cert:ignore",
                "+rfx",
                "/size:1920x1080",
                "/gdi:sw",
                "/log-level:INFO",
            ])
            .env("SDL_VIDEODRIVER", "dummy")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn script/sdl-freerdp"),
    );

    let deadline = Instant::now() + Duration::from_secs(15);
    let mut gdi = false;
    let mut last = String::new();
    while Instant::now() < deadline {
        last = std::fs::read_to_string(&log_path).unwrap_or_default();
        if last.contains("Local framebuffer format") && last.contains("PIXEL_FORMAT_BGRA32") {
            gdi = true;
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    drop(freerdp);
    drop(server);
    assert!(
        gdi,
        "T1-GFX-01 FreeRDP did not init GDI BGRA32 (second stack). log {}:\n{last}",
        log_path.display()
    );
}
