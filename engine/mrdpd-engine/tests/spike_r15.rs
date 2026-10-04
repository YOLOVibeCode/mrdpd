//! Spike R15 (branch `spike-r15-tab`, never merged): grab one frame from a live
//! `MRDPD_SPIKE_TAB=1 mrdpd-serve`, crop the tab area to `/tmp/mrdpd-r15-tab.bmp`, and hover the
//! tab once (the serve logs "R15: pointer over tab"). Set `MRDP_SPIKE_TAB_RECT=x,y,w,h` from
//! the serve's "R15: spike tab at" line.

mod common;

use std::env;
use std::time::Duration;

use ironrdp::pdu::input::fast_path::FastPathInputEvent;
use ironrdp::pdu::input::mouse::PointerFlags;
use ironrdp::pdu::input::MousePdu;

#[test]
#[ignore = "R15 spike: live MRDPD_SPIKE_TAB=1 mrdpd-serve"]
fn spike_r15_tab_crop_and_hover() {
    let read = |name: &str, default: u16| {
        env::var(name)
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(default)
    };
    let (port, width, height) = (
        read("MRDP_SERVE_PORT", 3390),
        read("MRDP_SERVE_WIDTH", 3360),
        read("MRDP_SERVE_HEIGHT", 1890),
    );
    let rect: Vec<u32> = env::var("MRDP_SPIKE_TAB_RECT")
        .expect("R15: MRDP_SPIKE_TAB_RECT=x,y,w,h")
        .split(',')
        .map(|v| v.trim().parse().expect("R15: rect numbers"))
        .collect();
    let (x, y, w, h) = (rect[0], rect[1], rect[2], rect[3]);

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
    .expect("R15: connect to mrdpd-serve");

    let full_width = u32::from(width);
    let cx0 = x.saturating_sub(w / 2);
    let cx1 = (x + w + w / 2).min(full_width);
    let cy0 = y;
    let cy1 = (y + h * 3).min(u32::from(height));
    let rgba = client.image.data();
    let mut crop = Vec::with_capacity(((cx1 - cx0) * (cy1 - cy0) * 4) as usize);
    for row in cy0..cy1 {
        let start = ((row * full_width + cx0) * 4) as usize;
        let end = ((row * full_width + cx1) * 4) as usize;
        crop.extend_from_slice(&rgba[start..end]);
    }
    common::write_bmp_bgr(
        std::path::Path::new("/tmp/mrdpd-r15-tab.bmp"),
        cx1 - cx0,
        cy1 - cy0,
        &crop,
    )
    .expect("R15: write crop");

    client
        .send_fastpath(&[FastPathInputEvent::MouseEvent(MousePdu {
            flags: PointerFlags::MOVE,
            number_of_wheel_rotation_units: 0,
            x_position: (x + w / 2) as u16,
            y_position: (y + h / 2) as u16,
        })])
        .expect("R15: hover move");
    std::thread::sleep(Duration::from_millis(300));
}
