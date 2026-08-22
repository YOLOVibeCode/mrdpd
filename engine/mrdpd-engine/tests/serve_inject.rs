//! T1-IN-04: FastPath mouse against a running `mrdpd-serve` (HID via `CGEventInputSink`).
//! Not part of `just test`. Needs Screen Recording + Accessibility and `just serve`.
//!
//! ```bash
//! just serve
//! cargo test --manifest-path engine/Cargo.toml -p mrdpd-engine --test serve_inject -- --ignored --nocapture
//! ```

mod common;

use std::env;
use std::time::Duration;

use ironrdp::pdu::input::fast_path::FastPathInputEvent;
use ironrdp::pdu::input::mouse::PointerFlags;
use ironrdp::pdu::input::MousePdu;

#[test]
#[ignore = "T1-IN-04: live mrdpd-serve; just serve then --ignored"]
fn t1_in_04_fastpath_mouse_against_live_serve() {
    let port: u16 = env::var("MRDP_SERVE_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(3390);
    let width: u16 = env::var("MRDP_SERVE_WIDTH")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(3360);
    let height: u16 = env::var("MRDP_SERVE_HEIGHT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(1890);
    let x = width / 2;
    let y = height / 2;

    let mut client = common::connect_until(
        "127.0.0.1",
        port,
        "mrdpd",
        "changeme",
        width,
        height,
        Duration::from_secs(20),
        |rgba| rgba.len() >= 16 && rgba.iter().any(|&b| b != 0),
    )
    .expect("T1-IN-04: connect to mrdpd-serve (just serve; Screen Recording + Accessibility)");

    client
        .send_fastpath(&[FastPathInputEvent::MouseEvent(MousePdu {
            flags: PointerFlags::MOVE,
            number_of_wheel_rotation_units: 0,
            x_position: x,
            y_position: y,
        })])
        .expect("T1-IN-04: FastPath mouse move");
    std::thread::sleep(Duration::from_millis(300));
}
