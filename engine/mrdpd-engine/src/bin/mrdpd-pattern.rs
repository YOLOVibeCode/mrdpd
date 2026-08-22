//! Lab process for M2 interop: serve `pattern::bgra_1080p_quadrants` on loopback.
//! ABI v1 only (T1-GFX-01). Default bind 127.0.0.1 (T1-SEC-04).

use std::ffi::{c_char, CString};
use std::ptr;

use mrdpd_engine::pattern::{self, HEIGHT, STRIDE, WIDTH};
use mrdpd_engine::{
    mrdpd_engine_push_frame, mrdpd_engine_start, mrdpd_engine_stop, MrdpdCallbacks, MrdpdEngineConfig,
    MrdpdFrame,
};

fn unspecified_bind(host: &str) -> bool {
    matches!(host, "0.0.0.0" | "::" | "*")
}

extern "C" fn on_log(_ud: *mut std::ffi::c_void, level: i32, msg: *const c_char) {
    if msg.is_null() {
        return;
    }
    let s = unsafe { std::ffi::CStr::from_ptr(msg) }.to_string_lossy();
    eprintln!("mrdpd-engine[{level}]: {s}");
}

fn main() {
    let mut args = std::env::args().skip(1);
    let host = args.next().unwrap_or_else(|| "127.0.0.1".to_owned());
    let port_s = args.next().unwrap_or_else(|| "3390".to_owned());
    let port: u16 = match port_s.parse() {
        Ok(p) if p != 0 => p,
        _ => {
            eprintln!("usage: mrdpd-pattern [host] [port]  (port 1..=65535, not 0)");
            std::process::exit(1);
        }
    };
    if unspecified_bind(&host) {
        eprintln!("T1-SEC-04: refuse unspecified bind {host}; pass 127.0.0.1 or an explicit iface");
        std::process::exit(4);
    }

    let host_c = CString::new(host.clone()).expect("host");
    let user = CString::new("mrdpd").unwrap();
    let pass = CString::new("changeme").unwrap();
    let cfg = MrdpdEngineConfig {
        bind_host: host_c.as_ptr(),
        bind_port: port,
        cert_path: ptr::null(),
        key_path: ptr::null(),
        nla_username: user.as_ptr(),
        nla_password: pass.as_ptr(),
        desktop_width: WIDTH as u16,
        desktop_height: HEIGHT as u16,
    };
    let cb = MrdpdCallbacks {
        userdata: ptr::null_mut(),
        on_mouse: None,
        on_key: None,
        on_client_connected: None,
        on_client_disconnected: None,
        on_log: Some(on_log),
    };

    let rc = mrdpd_engine_start(&cfg, &cb);
    if rc != 0 {
        eprintln!("mrdpd_engine_start failed rc={rc}");
        std::process::exit(rc);
    }

    let pixels = pattern::bgra_1080p_quadrants();
    let frame = MrdpdFrame {
        width: WIDTH,
        height: HEIGHT,
        stride: STRIDE,
        format: 1,
        pixels: pixels.as_ptr(),
        dirty_rects: ptr::null(),
        dirty_rect_count: 0,
    };
    let rc = mrdpd_engine_push_frame(&frame);
    if rc != 0 {
        eprintln!("mrdpd_engine_push_frame failed rc={rc}");
        let _ = mrdpd_engine_stop();
        std::process::exit(rc);
    }

    eprintln!("mrdpd-pattern listening {host}:{port} (NLA user mrdpd)");
    let _ = host_c;
    let _ = user;
    let _ = pass;
    let _ = pixels;
    std::thread::park();
    let _ = mrdpd_engine_stop();
}

#[cfg(test)]
mod tests {
    use super::unspecified_bind;

    #[test]
    fn t1_sec_04_refuses_unspecified_bind() {
        assert!(unspecified_bind("0.0.0.0"));
        assert!(unspecified_bind("::"));
        assert!(unspecified_bind("*"));
        assert!(!unspecified_bind("127.0.0.1"));
        assert!(!unspecified_bind("100.64.0.1"));
    }
}
