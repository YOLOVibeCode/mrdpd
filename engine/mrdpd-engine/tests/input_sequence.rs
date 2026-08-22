//! T1-IN-01 / T1-IN-03: FastPath mouse + scancode sequence over ABI callbacks.
//! No new C ABI. Retina mapping is M6. Bind 127.0.0.1 only (T1-SEC-04).

mod common;

use std::ffi::CString;
use std::sync::Mutex;
use std::time::Duration;

use ironrdp::pdu::input::fast_path::{FastPathInputEvent, KeyboardFlags};
use ironrdp::pdu::input::mouse::PointerFlags;
use ironrdp::pdu::input::MousePdu;
use mrdpd_engine::{MrdpdCallbacks, MrdpdEngineConfig, MrdpdFrame, MrdpdKeyEvent, MrdpdMouseEvent};

const WIDTH: u32 = 64;
const HEIGHT: u32 = 64;
const STRIDE: u32 = WIDTH * 4;

struct Rec {
    keys: Vec<MrdpdKeyEvent>,
    mice: Vec<MrdpdMouseEvent>,
}

extern "C" fn on_key(ud: *mut std::ffi::c_void, event: MrdpdKeyEvent) {
    let rec = unsafe { &*(ud as *const Mutex<Rec>) };
    rec.lock().unwrap().keys.push(event);
}

extern "C" fn on_mouse(ud: *mut std::ffi::c_void, event: MrdpdMouseEvent) {
    let rec = unsafe { &*(ud as *const Mutex<Rec>) };
    rec.lock().unwrap().mice.push(event);
}

fn solid_frame() -> Vec<u8> {
    vec![0xFF, 0x00, 0xFF, 0xFF].repeat((WIDTH * HEIGHT) as usize)
}

#[test]
fn t1_in_01_fastpath_sequence_reaches_abi_callbacks() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("error")),
        )
        .with_test_writer()
        .try_init();

    let rec = Box::new(Mutex::new(Rec {
        keys: Vec::new(),
        mice: Vec::new(),
    }));
    let rec_ptr = Box::into_raw(rec);

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
        userdata: rec_ptr.cast(),
        on_mouse: Some(on_mouse),
        on_key: Some(on_key),
        on_client_connected: None,
        on_client_disconnected: None,
        on_log: Some(common::on_log),
    };

    let rc = mrdpd_engine::mrdpd_engine_start(&cfg, &cb);
    assert_eq!(rc, 0, "start");

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
    assert_eq!(mrdpd_engine::mrdpd_engine_push_frame(&frame), 0);

    let host_s = "127.0.0.1".to_owned();
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    let _client = std::thread::Builder::new()
        .name("mrdpd-input-client".into())
        .spawn(move || {
            let result = (|| {
                let mut client = common::connect_until(
                    &host_s,
                    port,
                    "mrdpd",
                    "changeme",
                    WIDTH as u16,
                    HEIGHT as u16,
                    Duration::from_secs(8),
                    |rgba| {
                        rgba.chunks_exact(4).any(|px| {
                            px[0].abs_diff(0xFF) <= 8 && px[2].abs_diff(0xFF) <= 8
                        })
                    },
                )?;
                client.send_fastpath(&[
                    FastPathInputEvent::MouseEvent(MousePdu {
                        flags: PointerFlags::MOVE,
                        number_of_wheel_rotation_units: 0,
                        x_position: 100,
                        y_position: 200,
                    }),
                    FastPathInputEvent::KeyboardEvent(KeyboardFlags::empty(), 0x1E),
                    FastPathInputEvent::KeyboardEvent(KeyboardFlags::RELEASE, 0x1E),
                    FastPathInputEvent::MouseEvent(MousePdu {
                        flags: PointerFlags::LEFT_BUTTON | PointerFlags::DOWN,
                        number_of_wheel_rotation_units: 0,
                        x_position: 100,
                        y_position: 200,
                    }),
                    FastPathInputEvent::MouseEvent(MousePdu {
                        flags: PointerFlags::LEFT_BUTTON,
                        number_of_wheel_rotation_units: 0,
                        x_position: 100,
                        y_position: 200,
                    }),
                    FastPathInputEvent::MouseEvent(MousePdu {
                        flags: PointerFlags::VERTICAL_WHEEL,
                        number_of_wheel_rotation_units: 120,
                        x_position: 100,
                        y_position: 200,
                    }),
                ])?;
                std::thread::sleep(Duration::from_millis(400));
                Ok::<(), anyhow::Error>(())
            })();
            let _ = tx.send(result);
        })
        .expect("client thread");

    rx.recv_timeout(Duration::from_secs(20))
        .expect("input client timed out")
        .expect("FastPath send");

    let _ = mrdpd_engine::mrdpd_engine_stop();
    let rec = unsafe { Box::from_raw(rec_ptr) };
    let rec = rec.lock().unwrap();

    assert!(
        rec.keys.iter().any(|k| k.scancode == 0x1E && k.extended == 0 && k.pressed == 1)
            && rec.keys.iter().any(|k| k.scancode == 0x1E && k.extended == 0 && k.pressed == 0),
        "T1-IN-01 A down/up scancode 0x1E: {:?}",
        rec.keys.iter().map(|k| (k.scancode, k.extended, k.pressed)).collect::<Vec<_>>()
    );
    assert!(
        rec.mice.iter().any(|m| m.x == 100 && m.y == 200 && m.buttons == 0 && m.wheel == 0),
        "T1-IN-03 move 100,200: {:?}",
        rec.mice.iter().map(|m| (m.x, m.y, m.buttons, m.wheel)).collect::<Vec<_>>()
    );
    assert!(
        rec.mice.iter().any(|m| m.buttons == 1),
        "T1-IN-03 left down: {:?}",
        rec.mice.iter().map(|m| (m.x, m.y, m.buttons, m.wheel)).collect::<Vec<_>>()
    );
    assert!(
        rec.mice.iter().any(|m| m.wheel == 120),
        "T1-IN-03 vertical wheel: {:?}",
        rec.mice.iter().map(|m| (m.x, m.y, m.buttons, m.wheel)).collect::<Vec<_>>()
    );
}
