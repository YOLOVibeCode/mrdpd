//! Real engine: IronRDP behind ABI v1 (`docs/abi.md`).
//!
//! T1-SEC-01 TLS listen, T1-SEC-02 NLA (CredSSP Hybrid), T1-GFX-01 push_frame copy.

use std::ffi::{c_char, c_void, CStr, CString};
use std::net::{TcpListener, ToSocketAddrs};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use ironrdp_server::tokio::sync::mpsc;
use ironrdp_server::{Credentials, RdpServer, ServerEvent};

mod display;
mod input;
mod tls;
pub mod pattern;

use display::SharedDisplay;
use input::{ConnForwarder, InputForwarder};
use tls::TlsMaterial;

const MRDP_PIXEL_BGRA8888: u32 = 1;

const MRDPD_OK: i32 = 0;
const MRDPD_ERR_INVAL: i32 = 1;
const MRDPD_ERR_ALREADY_STARTED: i32 = 2;
const MRDPD_ERR_NOT_STARTED: i32 = 3;
const MRDPD_ERR_BIND: i32 = 4;
const MRDPD_ERR_CERT: i32 = 5;
const MRDPD_ERR_UNSUPPORTED: i32 = 6;
const MRDPD_ERR_INTERNAL: i32 = 7;

// Placeholder NLA when the caller leaves username/password NULL (ABI start tests).
// E2E uses the same pair; `changeme` is allowlisted in .gitleaks.toml.
const DEFAULT_NLA_USER: &str = "mrdpd";
const DEFAULT_NLA_PASS: &str = "changeme";

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdRect {
    pub x: i32,
    pub y: i32,
    pub w: u32,
    pub h: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdEngineConfig {
    pub bind_host: *const c_char,
    pub bind_port: u16,
    pub cert_path: *const c_char,
    pub key_path: *const c_char,
    pub nla_username: *const c_char,
    pub nla_password: *const c_char,
    pub desktop_width: u16,
    pub desktop_height: u16,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdFrame {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub format: u32,
    pub pixels: *const u8,
    pub dirty_rects: *const MrdpdRect,
    pub dirty_rect_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdMouseEvent {
    pub x: i32,
    pub y: i32,
    pub buttons: u32,
    pub wheel: i16,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdKeyEvent {
    pub scancode: u16,
    pub extended: u8,
    pub pressed: u8,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MrdpdCallbacks {
    pub userdata: *mut c_void,
    pub on_mouse: Option<extern "C" fn(*mut c_void, MrdpdMouseEvent)>,
    pub on_key: Option<extern "C" fn(*mut c_void, MrdpdKeyEvent)>,
    pub on_client_connected: Option<extern "C" fn(*mut c_void)>,
    pub on_client_disconnected: Option<extern "C" fn(*mut c_void, i32)>,
    pub on_log: Option<extern "C" fn(*mut c_void, i32, *const c_char)>,
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

// SAFETY: userdata is never dereferenced here; it is only handed back to C.
unsafe impl Send for MrdpdCallbacks {}
unsafe impl Sync for MrdpdCallbacks {}

struct Live {
    thread: Option<JoinHandle<()>>,
    events: mpsc::UnboundedSender<ServerEvent>,
    display: SharedDisplay,
    last_frame: Arc<Mutex<Option<Vec<u8>>>>,
}

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

pub(crate) fn fire_mouse(cbs: &MrdpdCallbacks, event: MrdpdMouseEvent) {
    CALLBACKS_IN_FLIGHT.fetch_add(1, Ordering::SeqCst);
    if let Some(cb) = cbs.on_mouse {
        cb(cbs.userdata, event);
    }
    CALLBACKS_IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
}

pub(crate) fn fire_key(cbs: &MrdpdCallbacks, event: MrdpdKeyEvent) {
    CALLBACKS_IN_FLIGHT.fetch_add(1, Ordering::SeqCst);
    if let Some(cb) = cbs.on_key {
        cb(cbs.userdata, event);
    }
    CALLBACKS_IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
}

pub(crate) fn fire_connected(cbs: &MrdpdCallbacks) {
    CALLBACKS_IN_FLIGHT.fetch_add(1, Ordering::SeqCst);
    if let Some(cb) = cbs.on_client_connected {
        cb(cbs.userdata);
    }
    CALLBACKS_IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
}

pub(crate) fn fire_disconnected(cbs: &MrdpdCallbacks, reason: i32) {
    CALLBACKS_IN_FLIGHT.fetch_add(1, Ordering::SeqCst);
    if let Some(cb) = cbs.on_client_disconnected {
        cb(cbs.userdata, reason);
    }
    CALLBACKS_IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
}

fn fire_log(cbs: &MrdpdCallbacks, level: i32, msg: &str) {
    let Ok(cmsg) = CString::new(msg) else {
        return;
    };
    CALLBACKS_IN_FLIGHT.fetch_add(1, Ordering::SeqCst);
    if let Some(cb) = cbs.on_log {
        cb(cbs.userdata, level, cmsg.as_ptr());
    }
    CALLBACKS_IN_FLIGHT.fetch_sub(1, Ordering::SeqCst);
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
    let nla_user = match copy_opt_cstr(cfg.nla_username) {
        Ok(v) => v,
        Err(code) => return code,
    };
    let nla_pass = match copy_opt_cstr(cfg.nla_password) {
        Ok(v) => v,
        Err(code) => return code,
    };

    let tls = match (cert.as_deref(), key.as_deref()) {
        (None, None) => match TlsMaterial::ephemeral() {
            Ok(t) => t,
            Err(code) => return code,
        },
        (Some(cert_path), Some(key_path)) => match TlsMaterial::from_paths(cert_path, key_path) {
            Ok(t) => t,
            Err(code) => return code,
        },
        _ => return MRDPD_ERR_INVAL,
    };

    let username = match nla_user.as_deref() {
        None => DEFAULT_NLA_USER.to_owned(),
        Some(s) if s.is_empty() => return MRDPD_ERR_INVAL,
        Some(s) => s.to_owned(),
    };
    let password = match nla_pass.as_deref() {
        None => DEFAULT_NLA_PASS.to_owned(),
        Some(s) if s.is_empty() => return MRDPD_ERR_INVAL,
        Some(s) => s.to_owned(),
    };

    let mut addrs = match (host.as_str(), cfg.bind_port).to_socket_addrs() {
        Ok(a) => a,
        Err(_) => return MRDPD_ERR_INVAL,
    };
    let probe_addr = match addrs.next() {
        Some(a) => a,
        None => return MRDPD_ERR_INVAL,
    };

    let mut engine = lock_engine();
    if engine.live.is_some() {
        return MRDPD_ERR_ALREADY_STARTED;
    }

    // Probe bind without SO_REUSEADDR so a live listener yields MRDPD_ERR_BIND
    // (IronRDP itself sets SO_REUSEADDR, which would hide the contract case).
    let probe = match TcpListener::bind(probe_addr) {
        Ok(l) => l,
        Err(_) => return MRDPD_ERR_BIND,
    };
    let bind_addr = match probe.local_addr() {
        Ok(a) => a,
        Err(_) => return MRDPD_ERR_INTERNAL,
    };
    drop(probe);

    let mut width = cfg.desktop_width;
    let mut height = cfg.desktop_height;
    if width == 0 {
        width = 64;
    }
    if height == 0 {
        height = 64;
    }

    let display = SharedDisplay::new(width, height);
    let last_frame = Arc::new(Mutex::new(None));
    let display_for_server = display.clone();
    let cbs_input = cbs;
    let cbs_conn = cbs;
    let cbs_log = cbs;
    let pub_key = tls.pub_key;
    let acceptor = tls.acceptor;
    let creds = Credentials {
        username,
        password,
        domain: None,
    };

    // T1-SEC-03: IronRDP 0.13 `run()` is sequential — `run_connection` blocks
    // the accept loop, so a second peer waits in the listen backlog (ADR 0004).
    // IronRDP's run() future is !Send (Rc in the session loop). Drive it on a
    // current-thread runtime in a dedicated OS thread.
    let (ev_tx, ev_rx) = std::sync::mpsc::sync_channel(1);
    let thread = match thread::Builder::new()
        .name("mrdpd-engine".into())
        .spawn(move || {
            let Ok(rt) = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            else {
                return;
            };
            let mut server = RdpServer::builder()
                .with_addr(bind_addr)
                .with_hybrid(acceptor, pub_key)
                .with_input_handler(InputForwarder::new(cbs_input))
                .with_display_handler(display_for_server)
                .with_connection_handler(Some(Box::new(ConnForwarder::new(cbs_conn))))
                .build();
            server.set_credentials(Some(creds));
            let ev = server.event_sender().clone();
            let _ = ev_tx.send(ev);
            rt.block_on(async move {
                if let Err(err) = server.run().await {
                    fire_log(&cbs_log, 3, &format!("ironrdp run: {err:#}"));
                }
            });
        }) {
        Ok(h) => h,
        Err(_) => return MRDPD_ERR_INTERNAL,
    };

    let ev = match ev_rx.recv_timeout(Duration::from_secs(5)) {
        Ok(ev) => ev,
        Err(_) => {
            let _ = thread.join();
            return MRDPD_ERR_INTERNAL;
        }
    };

    let (tx, rx) = ironrdp_server::tokio::sync::oneshot::channel();
    if ev.send(ServerEvent::GetLocalAddr(tx)).is_err() {
        let _ = ev.send(ServerEvent::Quit("start-failed".into()));
        let _ = thread.join();
        return MRDPD_ERR_INTERNAL;
    }
    let (done_tx, done_rx) = std::sync::mpsc::sync_channel(1);
    thread::spawn(move || {
        let _ = done_tx.send(rx.blocking_recv());
    });
    match done_rx.recv_timeout(Duration::from_secs(5)) {
        Ok(Ok(Some(_addr))) => {}
        Ok(Ok(None)) | Ok(Err(_)) | Err(_) => {
            let _ = ev.send(ServerEvent::Quit("bind-timeout".into()));
            let _ = thread.join();
            return MRDPD_ERR_INTERNAL;
        }
    }

    engine.live = Some(Live {
        thread: Some(thread),
        events: ev,
        display,
        last_frame,
    });
    MRDPD_OK
}

fn stop_inner() -> i32 {
    let (thread, events) = {
        let mut engine = lock_engine();
        match engine.live.take() {
            Some(mut live) => (live.thread.take(), Some(live.events)),
            None => return MRDPD_OK,
        }
    };
    if let Some(events) = events {
        let _ = events.send(ServerEvent::Quit("stop".into()));
    }
    if let Some(handle) = thread {
        let (done_tx, done_rx) = std::sync::mpsc::sync_channel(1);
        thread::spawn(move || {
            let _ = handle.join();
            let _ = done_tx.send(());
        });
        let _ = done_rx.recv_timeout(Duration::from_secs(2));
    }
    while CALLBACKS_IN_FLIGHT.load(Ordering::SeqCst) > 0 {
        thread::sleep(Duration::from_millis(1));
    }
    MRDPD_OK
}

fn push_frame_inner(frame: *const MrdpdFrame) -> i32 {
    let engine = lock_engine();
    let Some(live) = engine.live.as_ref() else {
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
    if frame.width > u32::from(u16::MAX) || frame.height > u32::from(u16::MAX) {
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
    let copy = pixels.to_vec();
    if live
        .display
        .push_bgra(
            frame.width as u16,
            frame.height as u16,
            frame.stride as usize,
            &copy,
        )
        .is_err()
    {
        return MRDPD_ERR_INVAL;
    }
    if let Ok(mut last) = live.last_frame.lock() {
        *last = Some(copy);
    }
    MRDPD_OK
}

#[cfg(feature = "test-hooks")]
fn copy_last_frame_inner(out: *mut u8, out_cap: u32, out_len: *mut u32) -> i32 {
    if out.is_null() || out_len.is_null() {
        return MRDPD_ERR_INVAL;
    }
    let engine = lock_engine();
    let Some(live) = engine.live.as_ref() else {
        return MRDPD_ERR_NOT_STARTED;
    };
    let Ok(guard) = live.last_frame.lock() else {
        return MRDPD_ERR_INTERNAL;
    };
    let Some(frame) = guard.as_ref() else {
        return MRDPD_ERR_INVAL;
    };
    let n = frame.len() as u32;
    // SAFETY: caller provides out_len.
    unsafe {
        *out_len = n;
    }
    if out_cap < n {
        return MRDPD_ERR_INVAL;
    }
    // SAFETY: caller buffer is at least out_cap bytes; we copy n <= out_cap.
    unsafe {
        std::ptr::copy_nonoverlapping(frame.as_ptr(), out, frame.len());
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

#[cfg(feature = "test-hooks")]
#[no_mangle]
pub extern "C" fn mrdpd_stub_copy_last_frame(out: *mut u8, out_cap: u32, out_len: *mut u32) -> i32 {
    ffi_guard(|| copy_last_frame_inner(out, out_cap, out_len))
}
