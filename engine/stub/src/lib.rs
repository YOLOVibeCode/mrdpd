//! StubEngine: the v1 C ABI with a dummy TCP listen. No IronRDP.

use std::ffi::{c_char, c_void, CStr};
use std::fs::File;
use std::io::ErrorKind;
use std::net::TcpListener;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::Duration;

const MRDP_PIXEL_BGRA8888: u32 = 1;

const MRDPD_OK: i32 = 0;
const MRDPD_ERR_INVAL: i32 = 1;
const MRDPD_ERR_ALREADY_STARTED: i32 = 2;
const MRDPD_ERR_NOT_STARTED: i32 = 3;
const MRDPD_ERR_BIND: i32 = 4;
const MRDPD_ERR_CERT: i32 = 5;
const MRDPD_ERR_UNSUPPORTED: i32 = 6;
const MRDPD_ERR_INTERNAL: i32 = 7;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdRect {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdEngineConfig {
    bind_host: *const c_char,
    bind_port: u16,
    cert_path: *const c_char,
    key_path: *const c_char,
    nla_username: *const c_char,
    nla_password: *const c_char,
    desktop_width: u16,
    desktop_height: u16,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdFrame {
    width: u32,
    height: u32,
    stride: u32,
    format: u32,
    pixels: *const u8,
    dirty_rects: *const MrdpdRect,
    dirty_rect_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdMouseEvent {
    x: i32,
    y: i32,
    buttons: u32,
    wheel: i16,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdKeyEvent {
    scancode: u16,
    extended: u8,
    pressed: u8,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdCallbacks {
    userdata: *mut c_void,
    on_mouse: Option<extern "C" fn(*mut c_void, MrdpdMouseEvent)>,
    on_key: Option<extern "C" fn(*mut c_void, MrdpdKeyEvent)>,
    on_client_connected: Option<extern "C" fn(*mut c_void)>,
    on_client_disconnected: Option<extern "C" fn(*mut c_void, i32)>,
    on_log: Option<extern "C" fn(*mut c_void, i32, *const c_char)>,
}

const _: () = {
    use std::mem::{offset_of, size_of};
    assert!(size_of::<MrdpdEngineConfig>() == 56);
    assert!(offset_of!(MrdpdEngineConfig, bind_host) == 0);
    assert!(offset_of!(MrdpdEngineConfig, bind_port) == 8);
    assert!(offset_of!(MrdpdEngineConfig, cert_path) == 16);
    assert!(offset_of!(MrdpdEngineConfig, key_path) == 24);
    assert!(offset_of!(MrdpdEngineConfig, nla_username) == 32);
    assert!(offset_of!(MrdpdEngineConfig, nla_password) == 40);
    assert!(offset_of!(MrdpdEngineConfig, desktop_width) == 48);
    assert!(offset_of!(MrdpdEngineConfig, desktop_height) == 50);
    assert!(size_of::<MrdpdFrame>() == 40);
    assert!(offset_of!(MrdpdFrame, pixels) == 16);
    assert!(offset_of!(MrdpdFrame, dirty_rects) == 24);
    assert!(offset_of!(MrdpdFrame, dirty_rect_count) == 32);
    assert!(size_of::<MrdpdRect>() == 16);
    assert!(size_of::<MrdpdMouseEvent>() == 16);
    assert!(size_of::<MrdpdKeyEvent>() == 4);
    assert!(size_of::<MrdpdCallbacks>() == 48);
};

struct StoredFrame {
    pixels: Vec<u8>,
}

struct Live {
    _listener: TcpListener,
    stop: Arc<AtomicBool>,
    accept: Option<JoinHandle<()>>,
    callbacks: MrdpdCallbacks,
    last_frame: Option<StoredFrame>,
}

// SAFETY: userdata is never dereferenced; it is only handed back to C callbacks.
// Live crosses threads only via the engine mutex / joined accept thread.
unsafe impl Send for Live {}

struct Engine {
    live: Option<Live>,
}

static ENGINE: Mutex<Engine> = Mutex::new(Engine { live: None });
static CALLBACKS_IN_FLIGHT: AtomicUsize = AtomicUsize::new(0);

fn lock_engine() -> MutexGuard<'static, Engine> {
    ENGINE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn ffi_guard(f: impl FnOnce() -> i32) -> i32 {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(code) => code,
        Err(_) => MRDPD_ERR_INTERNAL,
    }
}

fn copy_opt_cstr(ptr: *const c_char) -> Result<Option<String>, i32> {
    if ptr.is_null() {
        return Ok(None);
    }
    // SAFETY: caller borrows the NUL-terminated string for this call (docs/abi.md).
    let cstr = unsafe { CStr::from_ptr(ptr) };
    let s = cstr.to_str().map_err(|_| MRDPD_ERR_INVAL)?;
    Ok(Some(s.to_owned()))
}

fn copy_required_cstr(ptr: *const c_char) -> Result<String, i32> {
    match copy_opt_cstr(ptr)? {
        Some(s) if !s.is_empty() => Ok(s),
        _ => Err(MRDPD_ERR_INVAL),
    }
}

fn path_readable(path: &str) -> bool {
    File::open(path).is_ok()
}

fn accept_loop(listener: TcpListener, stop: Arc<AtomicBool>) {
    let _ = listener.set_nonblocking(true);
    while !stop.load(Ordering::SeqCst) {
        match listener.accept() {
            Ok(_) => {}
            Err(err)
                if err.kind() == ErrorKind::WouldBlock
                    || err.kind() == ErrorKind::TimedOut
                    || err.kind() == ErrorKind::Interrupted =>
            {
                thread::sleep(Duration::from_millis(5));
            }
            Err(_) => break,
        }
    }
}

fn start_inner(config: *const MrdpdEngineConfig, callbacks: *const MrdpdCallbacks) -> i32 {
    if config.is_null() || callbacks.is_null() {
        return MRDPD_ERR_INVAL;
    }
    // SAFETY: non-NULL pointers borrowed for this call.
    let cfg = unsafe { &*config };
    let cbs = unsafe { *callbacks };

    let host = match copy_required_cstr(cfg.bind_host) {
        Ok(h) => h,
        Err(code) => return code,
    };
    let cert = match copy_opt_cstr(cfg.cert_path) {
        Ok(v) => v,
        Err(code) => return code,
    };
    let key = match copy_opt_cstr(cfg.key_path) {
        Ok(v) => v,
        Err(code) => return code,
    };
    match copy_opt_cstr(cfg.nla_username) {
        Ok(_) => {}
        Err(code) => return code,
    }
    match copy_opt_cstr(cfg.nla_password) {
        Ok(_) => {}
        Err(code) => return code,
    }

    match (cert.as_deref(), key.as_deref()) {
        (None, None) => {}
        (Some(cert_path), Some(key_path)) => {
            if !path_readable(cert_path) || !path_readable(key_path) {
                return MRDPD_ERR_CERT;
            }
        }
        _ => return MRDPD_ERR_INVAL,
    }

    let mut engine = lock_engine();
    if engine.live.is_some() {
        return MRDPD_ERR_ALREADY_STARTED;
    }

    let listener = match TcpListener::bind((host.as_str(), cfg.bind_port)) {
        Ok(listener) => listener,
        Err(_) => return MRDPD_ERR_BIND,
    };
    let accept_listener = match listener.try_clone() {
        Ok(cloned) => cloned,
        Err(_) => return MRDPD_ERR_INTERNAL,
    };
    let stop = Arc::new(AtomicBool::new(false));
    let stop_thread = stop.clone();
    let accept = match thread::Builder::new()
        .name("mrdpd-stub-accept".into())
        .spawn(move || accept_loop(accept_listener, stop_thread))
    {
        Ok(handle) => handle,
        Err(_) => return MRDPD_ERR_INTERNAL,
    };

    engine.live = Some(Live {
        _listener: listener,
        stop,
        accept: Some(accept),
        callbacks: cbs,
        last_frame: None,
    });
    MRDPD_OK
}

fn stop_inner() -> i32 {
    let accept = {
        let mut engine = lock_engine();
        let Some(mut live) = engine.live.take() else {
            return MRDPD_OK;
        };
        live.stop.store(true, Ordering::SeqCst);
        live.accept.take()
    };
    if let Some(handle) = accept {
        let _ = handle.join();
    }
    while CALLBACKS_IN_FLIGHT.load(Ordering::SeqCst) > 0 {
        thread::sleep(Duration::from_millis(1));
    }
    MRDPD_OK
}

fn push_frame_inner(frame: *const MrdpdFrame) -> i32 {
    let mut engine = lock_engine();
    let Some(live) = engine.live.as_mut() else {
        return MRDPD_ERR_NOT_STARTED;
    };
    if frame.is_null() {
        return MRDPD_ERR_INVAL;
    }
    // SAFETY: non-NULL frame borrowed until this function returns.
    let frame = unsafe { &*frame };
    if frame.format != MRDP_PIXEL_BGRA8888 {
        return MRDPD_ERR_UNSUPPORTED;
    }
    let Some(min_stride) = frame.width.checked_mul(4) else {
        return MRDPD_ERR_INVAL;
    };
    if frame.width == 0 || frame.height == 0 || frame.pixels.is_null() || frame.stride < min_stride
    {
        return MRDPD_ERR_INVAL;
    }
    if frame.dirty_rect_count > 0 && frame.dirty_rects.is_null() {
        return MRDPD_ERR_INVAL;
    }
    let Some(nbytes) = (frame.stride as usize).checked_mul(frame.height as usize) else {
        return MRDPD_ERR_INVAL;
    };
    // SAFETY: caller guarantees `pixels` is valid for stride * height bytes until we return.
    let pixels = unsafe { std::slice::from_raw_parts(frame.pixels, nbytes) };
    live.last_frame = Some(StoredFrame {
        pixels: pixels.to_vec(),
    });
    MRDPD_OK
}

fn script_mouse_inner(event: *const MrdpdMouseEvent) -> i32 {
    if event.is_null() {
        return MRDPD_ERR_INVAL;
    }
    // SAFETY: non-NULL event borrowed for this call.
    let event = unsafe { *event };
    let (on_mouse, userdata) = {
        let engine = lock_engine();
        let Some(live) = engine.live.as_ref() else {
            return MRDPD_ERR_NOT_STARTED;
        };
        (live.callbacks.on_mouse, live.callbacks.userdata)
    };
    CALLBACKS_IN_FLIGHT.fetch_add(1, Ordering::SeqCst);
    if let Some(on_mouse) = on_mouse {
        on_mouse(userdata, event);
    }
    CALLBACKS_IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
    MRDPD_OK
}

fn copy_last_frame_inner(out: *mut u8, out_cap: u32, out_len: *mut u32) -> i32 {
    if out.is_null() || out_len.is_null() {
        return MRDPD_ERR_INVAL;
    }
    let engine = lock_engine();
    let Some(live) = engine.live.as_ref() else {
        return MRDPD_ERR_NOT_STARTED;
    };
    let Some(frame) = live.last_frame.as_ref() else {
        return MRDPD_ERR_INVAL;
    };
    let n = frame.pixels.len() as u32;
    // SAFETY: caller provides out_len.
    unsafe {
        *out_len = n;
    }
    if out_cap < n {
        return MRDPD_ERR_INVAL;
    }
    // SAFETY: caller buffer is at least out_cap bytes; we copy n <= out_cap.
    unsafe {
        std::ptr::copy_nonoverlapping(frame.pixels.as_ptr(), out, frame.pixels.len());
    }
    MRDPD_OK
}

#[no_mangle]
pub extern "C" fn mrdpd_engine_abi_version() -> u32 {
    1
}

#[no_mangle]
pub extern "C" fn mrdpd_engine_start(
    config: *const MrdpdEngineConfig,
    callbacks: *const MrdpdCallbacks,
) -> i32 {
    ffi_guard(|| start_inner(config, callbacks))
}

#[no_mangle]
pub extern "C" fn mrdpd_engine_stop() -> i32 {
    ffi_guard(stop_inner)
}

#[no_mangle]
pub extern "C" fn mrdpd_engine_push_frame(frame: *const MrdpdFrame) -> i32 {
    ffi_guard(|| push_frame_inner(frame))
}

#[no_mangle]
pub extern "C" fn mrdpd_stub_script_mouse(event: *const MrdpdMouseEvent) -> i32 {
    ffi_guard(|| script_mouse_inner(event))
}

#[no_mangle]
pub extern "C" fn mrdpd_stub_copy_last_frame(out: *mut u8, out_cap: u32, out_len: *mut u32) -> i32 {
    ffi_guard(|| copy_last_frame_inner(out, out_cap, out_len))
}
