//! T1-GFX-01 / T1-GFX-03: 1080p quadrant pattern through the real engine.
//!
//! Same layout as `SyntheticFrameSource.pattern1080p` (BGRA 2×2 fixture scaled).
//! Bind 127.0.0.1 only (T1-SEC-04). No new ABI (ISP).
//!
//! Wire codec is RemoteFX (T1-GFX-03): qoi/qoiz are compile-out so the
//! IronRDP session crate can decode. T1-GFX-02 RDP 6 / RLE is not exercised
//! while the client advertises RemoteFX.

mod common;

use std::ffi::CString;
use std::path::PathBuf;
use std::time::Duration;

use mrdpd_engine::pattern::{self, HEIGHT, STRIDE, WIDTH};
use mrdpd_engine::{MrdpdCallbacks, MrdpdEngineConfig, MrdpdFrame};

/// RemoteFX at 1080p is lossy near quadrant edges; sample interiors.
const RFX_TOLERANCE: u8 = 24;

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
    let tl = sample_rgba(rgba, 480, 270);
    let tr = sample_rgba(rgba, 1440, 270);
    let bl = sample_rgba(rgba, 480, 810);
    let br = sample_rgba(rgba, 1440, 810);
    near(tl, [0xFF, 0x00, 0x00], RFX_TOLERANCE)
        && near(tr, [0x00, 0xFF, 0x00], RFX_TOLERANCE)
        && near(bl, [0x00, 0x00, 0xFF], RFX_TOLERANCE)
        && near(br, [0xFF, 0xFF, 0xFF], RFX_TOLERANCE)
}

#[test]
fn t1_gfx_01_headless_1080p_quadrants() {
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

    let pixels = pattern::bgra_1080p_quadrants();
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
    assert_eq!(rc, 0, "push_frame 1080p quadrants (T1-GFX-01)");

    let host_s = "127.0.0.1".to_owned();
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    let _client = std::thread::Builder::new()
        .name("mrdpd-e2e-1080".into())
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
        .expect("headless 1080p client timed out (T1-GFX-01/03)");
    let rgba = result.expect("headless 1080p screenshot");
    let _ = mrdpd_engine::mrdpd_engine_stop();

    let out = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join("e2e-1080p.bmp");
    if let Some(parent) = out.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = common::write_bmp_bgr(&out, WIDTH, HEIGHT, &rgba);

    assert_eq!(rgba.len(), (WIDTH * HEIGHT * 4) as usize, "RGBA buffer");
    let tl = sample_rgba(&rgba, 480, 270);
    let tr = sample_rgba(&rgba, 1440, 270);
    let bl = sample_rgba(&rgba, 480, 810);
    let br = sample_rgba(&rgba, 1440, 810);
    assert!(
        near(tl, [0xFF, 0x00, 0x00], RFX_TOLERANCE),
        "T1-GFX-01/03 top-left red, got {tl:?} (bmp {:?})",
        out
    );
    assert!(
        near(tr, [0x00, 0xFF, 0x00], RFX_TOLERANCE),
        "T1-GFX-01/03 top-right green, got {tr:?} (bmp {:?})",
        out
    );
    assert!(
        near(bl, [0x00, 0x00, 0xFF], RFX_TOLERANCE),
        "T1-GFX-01/03 bottom-left blue, got {bl:?} (bmp {:?})",
        out
    );
    assert!(
        near(br, [0xFF, 0xFF, 0xFF], RFX_TOLERANCE),
        "T1-GFX-01/03 bottom-right white, got {br:?} (bmp {:?})",
        out
    );
}
