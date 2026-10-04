//! T1-IN-04: FastPath mouse against a running `mrdpd-serve` (HID via `CGEventInputSink`).
//! T1-MON-02: with `--display`, the move lands on the served display.
//! Not part of `just test`. Needs Screen Recording + Accessibility and `just serve`.
//!
//! ```bash
//! just serve
//! just test-inject
//! just serve display=A
//! just test-inject-display frame=-2869,-2160,3840,2160 width=3840 height=2160
//! ```

mod common;

use std::env;
use std::time::Duration;

use ironrdp::pdu::input::fast_path::FastPathInputEvent;
use ironrdp::pdu::input::mouse::PointerFlags;
use ironrdp::pdu::input::MousePdu;

/// `MRDP_SERVE_PORT` / `MRDP_SERVE_WIDTH` / `MRDP_SERVE_HEIGHT`, defaulting to the lab panel.
fn serve_env() -> (u16, u16, u16) {
    let read = |name: &str, default: u16| {
        env::var(name)
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(default)
    };
    (
        read("MRDP_SERVE_PORT", 3390),
        read("MRDP_SERVE_WIDTH", 3360),
        read("MRDP_SERVE_HEIGHT", 1890),
    )
}

fn connect_and_move_to_center(port: u16, width: u16, height: u16) {
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
            x_position: width / 2,
            y_position: height / 2,
        })])
        .expect("T1-IN-04: FastPath mouse move");
    std::thread::sleep(Duration::from_millis(300));
}

#[test]
#[ignore = "T1-IN-04: live mrdpd-serve; just serve then --ignored"]
fn t1_in_04_fastpath_mouse_against_live_serve() {
    let (port, width, height) = serve_env();
    connect_and_move_to_center(port, width, height);
}

/// Set `MRDP_SERVE_FRAME=x,y,w,h` from the `mrdpd-serve` display listing, and
/// `MRDP_SERVE_WIDTH` / `MRDP_SERVE_HEIGHT` to the session size it prints.
#[test]
#[ignore = "T1-MON-02: live mrdpd-serve --display; set MRDP_SERVE_FRAME"]
fn t1_mon_02_fastpath_mouse_lands_on_served_display() {
    let frame: Vec<f64> = env::var("MRDP_SERVE_FRAME")
        .expect("T1-MON-02: MRDP_SERVE_FRAME=x,y,w,h from the mrdpd-serve listing")
        .split(',')
        .map(|v| v.trim().parse().expect("T1-MON-02: MRDP_SERVE_FRAME numbers"))
        .collect();
    assert_eq!(frame.len(), 4, "T1-MON-02: MRDP_SERVE_FRAME=x,y,w,h");
    let (port, width, height) = serve_env();

    let saved = quartz::cursor();
    connect_and_move_to_center(port, width, height);
    let at = quartz::cursor();
    quartz::warp(saved);

    let (cx, cy) = (frame[0] + frame[2] / 2.0, frame[1] + frame[3] / 2.0);
    assert!(
        (at.x - cx).abs() <= 2.0 && (at.y - cy).abs() <= 2.0,
        "T1-MON-02: cursor at ({:.0},{:.0}); served display center is ({cx:.0},{cy:.0})",
        at.x,
        at.y
    );
}

/// Quartz cursor location in global points (macOS).
mod quartz {
    use std::ffi::c_void;

    #[repr(C)]
    #[derive(Clone, Copy, Debug)]
    pub struct Point {
        pub x: f64,
        pub y: f64,
    }

    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGEventCreate(source: *const c_void) -> *mut c_void;
        fn CGEventGetLocation(event: *mut c_void) -> Point;
        fn CGWarpMouseCursorPosition(point: Point) -> i32;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFRelease(cf: *const c_void);
    }

    pub fn cursor() -> Point {
        // SAFETY: CGEventCreate(NULL) returns an owned event (checked non-NULL) that we release.
        unsafe {
            let event = CGEventCreate(std::ptr::null());
            assert!(!event.is_null(), "CGEventCreate returned NULL");
            let point = CGEventGetLocation(event);
            CFRelease(event);
            point
        }
    }

    pub fn warp(point: Point) {
        // SAFETY: plain value argument; no pointers.
        unsafe {
            CGWarpMouseCursorPosition(point);
        }
    }
}
