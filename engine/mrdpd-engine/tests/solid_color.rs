//! T1-SEC-01 / T1-SEC-02 / T1-GFX-01: headless IronRDP client screenshots a solid color.
//!
//! Golden: #FF00FF (magenta). Bind 127.0.0.1 only (T1-SEC-04).
//! Encode path is RemoteFX: `ironrdp-server` is built without qoi/qoiz so the
//! session crate can decode the surface (codec 11 / QoiZ is unsupported).

mod common;

use std::ffi::CString;
use std::path::PathBuf;
use std::time::Duration;

use mrdpd_engine::{MrdpdCallbacks, MrdpdEngineConfig, MrdpdFrame};

const MAGENTA_BGRA: [u8; 4] = [0xFF, 0x00, 0xFF, 0xFF];
const WIDTH: u32 = 64;
const HEIGHT: u32 = 64;
const STRIDE: u32 = WIDTH * 4;

fn solid_frame() -> Vec<u8> {
    let mut pixels = vec![0u8; (STRIDE * HEIGHT) as usize];
    for px in pixels.chunks_exact_mut(4) {
        px.copy_from_slice(&MAGENTA_BGRA);
    }
    pixels
}

#[test]
fn t1_gfx_01_headless_solid_magenta() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("error")),
        )
        .with_test_writer()
        .try_init();

    let host = CString::new("127.0.0.1").unwrap();
    let user = CString::new("mrdpd").unwrap();
    let pass = CString::new("changeme").unwrap();
    let port = common::free_loopback_port();

    let cfg = MrdpdEngineConfig {
        bind_host: host.as_ptr(),
        bind_port: port,
        cert_path: std::ptr::null(),
        key_path: std::ptr::null(),
        nla_username: user.as_ptr(),
        nla_password: pass.as_ptr(),
        desktop_width: WIDTH as u16,
        desktop_height: HEIGHT as u16,
    };
    let cb = MrdpdCallbacks {
        userdata: std::ptr::null_mut(),
        on_mouse: None,
        on_key: None,
        on_client_connected: None,
        on_client_disconnected: None,
        on_log: Some(common::on_log),
    };

    let rc = mrdpd_engine::mrdpd_engine_start(&cfg, &cb);
    assert_eq!(rc, 0, "start (T1-SEC-01 listen)");

    let pixels = solid_frame();
    let frame = MrdpdFrame {
        width: WIDTH,
        height: HEIGHT,
        stride: STRIDE,
        format: 1,
        pixels: pixels.as_ptr(),
        dirty_rects: std::ptr::null(),
        dirty_rect_count: 0,
    };
    let rc = mrdpd_engine::mrdpd_engine_push_frame(&frame);
    assert_eq!(rc, 0, "push_frame magenta (T1-GFX-01)");

    let host_s = "127.0.0.1".to_owned();
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    let _client = std::thread::Builder::new()
        .name("mrdpd-e2e-client".into())
        .spawn(move || {
            let result = common::screenshot(
                &host_s,
                port,
                "mrdpd",
                "changeme",
                WIDTH as u16,
                HEIGHT as u16,
                Duration::from_secs(8),
                |rgba| {
                    rgba.chunks_exact(4)
                        .any(|px| px[0].abs_diff(0xFF) <= 8 && px[2].abs_diff(0xFF) <= 8)
                },
            );
            let _ = tx.send(result);
        })
        .expect("client thread");
    let result = rx
        .recv_timeout(Duration::from_secs(15))
        .expect("headless client timed out (T1-SEC-01/02 handshake)");
    let rgba = result.expect("headless screenshot");
    let _ = mrdpd_engine::mrdpd_engine_stop();

    let out = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join("e2e-solid.bmp");
    if let Some(parent) = out.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = common::write_bmp_bgr(&out, WIDTH, HEIGHT, &rgba);

    assert_eq!(rgba.len(), (WIDTH * HEIGHT * 4) as usize, "RGBA buffer");
    let mut mismatches = 0u32;
    for px in rgba.chunks_exact(4) {
        let r_ok = px[0].abs_diff(0xFF) <= 2;
        let g_ok = px[1].abs_diff(0x00) <= 2;
        let b_ok = px[2].abs_diff(0xFF) <= 2;
        if !(r_ok && g_ok && b_ok) {
            mismatches += 1;
        }
    }
    assert_eq!(
        mismatches, 0,
        "expected solid #FF00FF (T1-GFX-01); {mismatches} pixels off (bmp {:?})",
        out
    );
}
