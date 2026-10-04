//! Live loop (`just live-check`): T1-IN-03, T1-IN-04, T1-PERF-02, T1-PERF-03, T1-PERF-04.
//!
//! Spawns `mrdpd-probe` (a full-screen input oracle on the captured display) and
//! `mrdpd-serve`, drives them with the headless IronRDP client, and asserts on both
//! sides: the HID event the Mac received (probe stdout) and the pixels the client saw.
//!
//! Not part of `just test`. Needs Screen Recording + Accessibility on the launching
//! terminal, takes over the first display for a few seconds per test, and must run
//! with `--test-threads=1`. Bind 127.0.0.1 only (T1-SEC-04).

mod common;

use std::io::{BufRead as _, BufReader};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

use ironrdp::pdu::input::fast_path::{FastPathInputEvent, KeyboardFlags};
use ironrdp::pdu::input::mouse::PointerFlags;
use ironrdp::pdu::input::MousePdu;

static ONE_LAB: Mutex<()> = Mutex::new(());

const SC_LSHIFT: u8 = 0x2A;
const SC_LGUI: u8 = 0x5B; // extended → Command
const SC_A: u8 = 0x1E;

struct KillOnDrop(Child);

impl Drop for KillOnDrop {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[derive(Debug, Clone)]
struct ProbeLine(Vec<(String, String)>);

impl ProbeLine {
    fn parse(line: &str) -> Self {
        Self(
            line.split_whitespace()
                .filter_map(|kv| kv.split_once('='))
                .map(|(k, v)| (k.to_owned(), v.to_owned()))
                .collect(),
        )
    }

    fn get(&self, key: &str) -> Option<&str> {
        self.0.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
    }

    fn ev(&self) -> &str {
        self.get("ev").unwrap_or("")
    }

    fn num(&self, key: &str) -> f64 {
        self.get(key).and_then(|v| v.parse().ok()).unwrap_or(f64::NAN)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Paint {
    Idle,
    Red,
    Green,
    Magenta,
    Yellow,
    Blue,
    Cyan,
    White,
    Other,
}

fn classify(r: u8, g: u8, b: u8) -> Paint {
    let hi = |c: u8| c > 160;
    let lo = |c: u8| c < 100;
    let mid = |c: u8| (30..=100).contains(&c);
    match (r, g, b) {
        _ if mid(r) && mid(g) && mid(b) && r.abs_diff(g) < 25 && g.abs_diff(b) < 25 => Paint::Idle,
        _ if hi(r) && hi(g) && hi(b) => Paint::White,
        _ if hi(r) && lo(g) && lo(b) => Paint::Red,
        _ if lo(r) && hi(g) && lo(b) => Paint::Green,
        _ if hi(r) && lo(g) && hi(b) => Paint::Magenta,
        _ if hi(r) && hi(g) && lo(b) => Paint::Yellow,
        _ if lo(r) && lo(g) && hi(b) => Paint::Blue,
        _ if lo(r) && hi(g) && hi(b) => Paint::Cyan,
        _ => Paint::Other,
    }
}

/// Average a 5×5 block in the lower-left tenth, away from the cursor path.
fn paint_at_sample(rgba: &[u8], width: u16, height: u16) -> Paint {
    let (w, h) = (u32::from(width), u32::from(height));
    let (cx, cy) = (w / 10, h * 9 / 10);
    let (mut r, mut g, mut b) = (0u32, 0u32, 0u32);
    for dy in 0..5 {
        for dx in 0..5 {
            let i = (((cy + dy) * w + cx + dx) * 4) as usize;
            if i + 2 >= rgba.len() {
                return Paint::Other;
            }
            r += u32::from(rgba[i]);
            g += u32::from(rgba[i + 1]);
            b += u32::from(rgba[i + 2]);
        }
    }
    classify((r / 25) as u8, (g / 25) as u8, (b / 25) as u8)
}

fn bin(name: &str) -> PathBuf {
    let dir = std::env::var_os("MRDPD_BIN_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../.build/debug"));
    let path = dir.join(name);
    assert!(
        path.exists(),
        "{} missing; build it first (`just live-check` runs `swift build`)",
        path.display()
    );
    path
}

/// Scancode set 1 for the typing check, with whether Shift is needed.
fn scancode(c: char) -> (u8, bool) {
    let shift = c.is_ascii_uppercase();
    let sc = match c.to_ascii_lowercase() {
        'a' => 0x1E, 'b' => 0x30, 'c' => 0x2E, 'd' => 0x20, 'e' => 0x12, 'f' => 0x21,
        'g' => 0x22, 'h' => 0x23, 'i' => 0x17, 'j' => 0x24, 'k' => 0x25, 'l' => 0x26,
        'm' => 0x32, 'n' => 0x31, 'o' => 0x18, 'p' => 0x19, 'q' => 0x10, 'r' => 0x13,
        's' => 0x1F, 't' => 0x14, 'u' => 0x16, 'v' => 0x2F, 'w' => 0x11, 'x' => 0x2D,
        'y' => 0x15, 'z' => 0x2C, '1' => 0x02, '2' => 0x03, '3' => 0x04, '4' => 0x05,
        '5' => 0x06, '6' => 0x07, '7' => 0x08, '8' => 0x09, '9' => 0x0A, '0' => 0x0B,
        ' ' => 0x39,
        other => panic!("live-check keymap has no {other:?}"),
    };
    (sc, shift)
}

struct Lab {
    _one: MutexGuard<'static, ()>,
    _probe: KillOnDrop,
    _probe_stdin: ChildStdin,
    probe_rx: Receiver<ProbeLine>,
    serve: KillOnDrop,
    client: common::ActiveClient,
    width: u16,
    height: u16,
    /// Captured display in Quartz global points: x, y, w, h.
    display: [f64; 4],
    focused: bool,
}

impl Lab {
    fn start() -> Self {
        let one = ONE_LAB.lock().unwrap_or_else(|e| e.into_inner());

        let mut probe = KillOnDrop(
            Command::new(bin("mrdpd-probe"))
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::inherit())
                .spawn()
                .expect("spawn mrdpd-probe"),
        );
        let probe_stdin = probe.0.stdin.take().expect("probe stdin");
        let probe_out = probe.0.stdout.take().expect("probe stdout");
        let (tx, probe_rx) = mpsc::channel();
        std::thread::spawn(move || {
            for line in BufReader::new(probe_out).lines().map_while(Result::ok) {
                if tx.send(ProbeLine::parse(&line)).is_err() {
                    return;
                }
            }
        });
        let ready = probe_rx
            .recv_timeout(Duration::from_secs(15))
            .expect("mrdpd-probe did not start");
        assert_eq!(ready.ev(), "ready", "mrdpd-probe: {ready:?} (Screen Recording TCC?)");
        let display = [ready.num("x"), ready.num("y"), ready.num("w"), ready.num("h")];

        let port = common::free_loopback_port();
        let mut serve = KillOnDrop(
            Command::new(bin("mrdpd-serve"))
                .args(["127.0.0.1", &port.to_string()])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::piped())
                .spawn()
                .expect("spawn mrdpd-serve"),
        );
        let (width, height) = wait_serve_listening(&mut serve);

        let mut client = common::connect_until(
            "127.0.0.1",
            port,
            "mrdpd",
            "changeme",
            width,
            height,
            Duration::from_secs(20),
            |rgba| paint_at_sample(rgba, width, height) == Paint::Idle,
        )
        .expect("connect to mrdpd-serve");
        assert_eq!(
            paint_at_sample(client.image.data(), width, height),
            Paint::Idle,
            "client never saw the probe window (is the probe on the captured display?)"
        );
        client.set_read_timeout(Duration::from_millis(20)).expect("read timeout");

        let mut lab = Self {
            _one: one,
            _probe: probe,
            _probe_stdin: probe_stdin,
            probe_rx,
            serve,
            client,
            width,
            height,
            display,
            focused: false,
        };
        // Activation click: a click on an inactive app's window makes it key.
        let (cx, cy) = (width / 2, height / 2);
        lab.mouse(PointerFlags::MOVE, cx, cy);
        lab.mouse(PointerFlags::LEFT_BUTTON | PointerFlags::DOWN, cx, cy);
        lab.mouse(PointerFlags::LEFT_BUTTON, cx, cy);
        lab.expect_probe("leftUp", Duration::from_secs(5));
        lab.wait_paint(Paint::Green, Duration::from_secs(5))
            .expect("activation click never reached the client's screen");
        let deadline = Instant::now() + Duration::from_secs(3);
        while !lab.focused && Instant::now() < deadline {
            lab.next_probe(Duration::from_millis(50));
        }
        lab
    }

    fn send(&mut self, events: &[FastPathInputEvent]) {
        self.client.send_fastpath(events).expect("send FastPath input");
    }

    fn mouse(&mut self, flags: PointerFlags, x: u16, y: u16) {
        self.send(&[FastPathInputEvent::MouseEvent(MousePdu {
            flags,
            number_of_wheel_rotation_units: 0,
            x_position: x,
            y_position: y,
        })]);
    }

    fn wheel(&mut self, units: i16, x: u16, y: u16) {
        self.send(&[FastPathInputEvent::MouseEvent(MousePdu {
            flags: PointerFlags::VERTICAL_WHEEL,
            number_of_wheel_rotation_units: units,
            x_position: x,
            y_position: y,
        })]);
    }

    fn key(&mut self, scancode: u8, extended: bool, down: bool) {
        let mut flags = KeyboardFlags::empty();
        if extended {
            flags |= KeyboardFlags::EXTENDED;
        }
        if !down {
            flags |= KeyboardFlags::RELEASE;
        }
        self.send(&[FastPathInputEvent::KeyboardEvent(flags, scancode)]);
    }

    /// Never type unless the probe holds keyboard focus: keys would land in another app.
    fn require_focus(&mut self) {
        while self.next_probe(Duration::ZERO).is_some() {}
        assert!(
            self.focused,
            "mrdpd-probe is not the key window; refusing to inject keys into another app"
        );
    }

    /// Next probe line, keeping the RDP socket drained meanwhile.
    fn next_probe(&mut self, timeout: Duration) -> Option<ProbeLine> {
        let deadline = Instant::now() + timeout;
        loop {
            if let Ok(line) = self.probe_rx.try_recv() {
                match line.ev() {
                    "key" => self.focused = true,
                    "resignKey" => self.focused = false,
                    "escape" | "timeout" | "error" => panic!("mrdpd-probe stopped: {line:?}"),
                    _ => {}
                }
                return Some(line);
            }
            if Instant::now() >= deadline {
                return None;
            }
            self.client.pump_once().expect("pump RDP session");
        }
    }

    fn expect_probe(&mut self, ev: &str, timeout: Duration) -> ProbeLine {
        let deadline = Instant::now() + timeout;
        while let Some(line) = self.next_probe(deadline.saturating_duration_since(Instant::now())) {
            if line.ev() == ev {
                return line;
            }
        }
        panic!("mrdpd-probe never reported ev={ev} within {timeout:?}");
    }

    fn paint(&self) -> Paint {
        paint_at_sample(self.client.image.data(), self.width, self.height)
    }

    /// Time until the client's framebuffer shows `want` at the sample point.
    fn wait_paint(&mut self, want: Paint, timeout: Duration) -> Option<Duration> {
        let start = Instant::now();
        loop {
            if self.paint() == want {
                return Some(start.elapsed());
            }
            if start.elapsed() > timeout {
                return None;
            }
            self.client.pump_once().expect("pump RDP session");
        }
    }

    /// Quartz point the Mac should see for an RDP pixel (T1-IN-03).
    fn expected_point(&self, x: u16, y: u16) -> (f64, f64) {
        let [ox, oy, w, h] = self.display;
        (
            ox + f64::from(x) * w / f64::from(self.width),
            oy + f64::from(y) * h / f64::from(self.height),
        )
    }

    fn assert_at(&self, line: &ProbeLine, x: u16, y: u16) {
        let (ex, ey) = self.expected_point(x, y);
        let (gx, gy) = (line.num("x"), line.num("y"));
        assert!(
            (gx - ex).abs() <= 1.5 && (gy - ey).abs() <= 1.5,
            "{} at ({gx},{gy}); expected ({ex},{ey}) for RDP ({x},{y})",
            line.ev()
        );
    }

    /// Bytes the client received and CPU seconds `mrdpd-serve` used over `window`.
    fn idle_window(&mut self, window: Duration) -> (usize, f64) {
        let cpu0 = cpu_seconds(self.serve.0.id());
        let start = Instant::now();
        let mut bytes = 0usize;
        while start.elapsed() < window {
            bytes += self.client.pump_once().expect("pump RDP session");
        }
        let cpu1 = cpu_seconds(self.serve.0.id());
        (bytes, cpu1 - cpu0)
    }
}

fn wait_serve_listening(serve: &mut KillOnDrop) -> (u16, u16) {
    let stderr = serve.0.stderr.take().expect("serve stderr");
    let (tx, rx) = mpsc::sync_channel(1);
    std::thread::spawn(move || {
        let mut sent = false;
        for line in BufReader::new(stderr).lines().map_while(Result::ok) {
            eprintln!("{line}");
            if !sent && line.contains("listening") {
                let _ = tx.send(line);
                sent = true;
            }
        }
    });
    let line = rx
        .recv_timeout(Duration::from_secs(30))
        .expect("mrdpd-serve did not print listening (TCC? see docs/tcc.md)");
    // "mrdpd-serve listening 127.0.0.1:PORT WxH (NLA user mrdpd)"
    let size = line.split_whitespace().nth(3).expect("size token");
    let (w, h) = size.split_once('x').expect("WxH");
    (w.parse().expect("width"), h.parse().expect("height"))
}

/// User + system CPU seconds of `pid` (`ps -o time=`, `[[dd-]hh:]mm:ss.cc`).
fn cpu_seconds(pid: u32) -> f64 {
    let out = Command::new("ps")
        .args(["-o", "time=", "-p", &pid.to_string()])
        .output()
        .expect("ps");
    let text = String::from_utf8_lossy(&out.stdout);
    text.trim()
        .split(':')
        .fold(0.0, |acc, part| acc * 60.0 + part.parse::<f64>().unwrap_or(0.0))
}

#[test]
#[ignore = "live: just live-check"]
fn t1_in_03_live_click_lands_on_mapped_point() {
    let mut lab = Lab::start();
    let (x, y) = (lab.width * 3 / 4, lab.height / 3);
    lab.mouse(PointerFlags::MOVE, x, y);
    lab.mouse(PointerFlags::LEFT_BUTTON | PointerFlags::DOWN, x, y);
    let down = lab.expect_probe("leftDown", Duration::from_secs(3));
    lab.assert_at(&down, x, y);
    assert!(lab.wait_paint(Paint::Red, Duration::from_secs(2)).is_some(), "no red after leftDown");
    lab.mouse(PointerFlags::LEFT_BUTTON, x, y);
    let up = lab.expect_probe("leftUp", Duration::from_secs(3));
    lab.assert_at(&up, x, y);
    assert!(lab.wait_paint(Paint::Green, Duration::from_secs(2)).is_some(), "no green after leftUp");
    println!("LIVE T1-IN-03 click ok at RDP ({x},{y})");
}

#[test]
#[ignore = "live: just live-check"]
fn t1_in_03_live_right_click() {
    let mut lab = Lab::start();
    let (x, y) = (lab.width / 4, lab.height / 3);
    lab.mouse(PointerFlags::MOVE, x, y);
    lab.mouse(PointerFlags::RIGHT_BUTTON | PointerFlags::DOWN, x, y);
    let down = lab.expect_probe("rightDown", Duration::from_secs(3));
    lab.assert_at(&down, x, y);
    assert!(lab.wait_paint(Paint::Magenta, Duration::from_secs(2)).is_some(), "no magenta after rightDown");
    lab.mouse(PointerFlags::RIGHT_BUTTON, x, y);
    lab.expect_probe("rightUp", Duration::from_secs(3));
    println!("LIVE T1-IN-03 right click ok");
}

#[test]
#[ignore = "live: just live-check"]
fn t1_in_03_live_drag() {
    let mut lab = Lab::start();
    let y = lab.height / 2;
    let (x0, x1) = (lab.width / 3, lab.width * 2 / 3);
    lab.mouse(PointerFlags::MOVE, x0, y);
    lab.mouse(PointerFlags::LEFT_BUTTON | PointerFlags::DOWN, x0, y);
    lab.expect_probe("leftDown", Duration::from_secs(3));
    for step in 1..=10u16 {
        let x = x0 + (x1 - x0) * step / 10;
        lab.mouse(PointerFlags::MOVE, x, y);
        std::thread::sleep(Duration::from_millis(15));
    }
    assert!(lab.wait_paint(Paint::Yellow, Duration::from_secs(2)).is_some(), "no yellow while dragging");
    lab.mouse(PointerFlags::LEFT_BUTTON, x1, y);
    let mut drags = Vec::new();
    loop {
        let line = lab.next_probe(Duration::from_secs(3)).expect("drag never finished with leftUp");
        match line.ev() {
            "leftDragged" => drags.push(line),
            "leftUp" => {
                lab.assert_at(&line, x1, y);
                break;
            }
            _ => {}
        }
    }
    assert!(drags.len() >= 5, "only {} leftDragged events for 10 moves", drags.len());
    lab.assert_at(drags.last().expect("drag"), x1, y);
    println!("LIVE T1-IN-03 drag ok ({} leftDragged)", drags.len());
}

#[test]
#[ignore = "live: just live-check"]
fn t1_in_03_live_vertical_wheel() {
    let mut lab = Lab::start();
    let (x, y) = (lab.width / 2, lab.height / 2);
    lab.wheel(120, x, y);
    let a = lab.expect_probe("scroll", Duration::from_secs(3));
    assert!(lab.wait_paint(Paint::Blue, Duration::from_secs(2)).is_some(), "no blue after wheel");
    lab.wheel(-120, x, y);
    let b = lab.expect_probe("scroll", Duration::from_secs(3));
    let (da, db) = (a.num("dy"), b.num("dy"));
    assert!(da != 0.0 && db != 0.0 && da.signum() != db.signum(), "wheel +120/-120 gave dy {da} / {db}");
    println!(
        "LIVE T1-IN-03 wheel ok: +120 → dy {da}, -120 → dy {db} (inverted={})",
        a.get("inverted").unwrap_or("?")
    );
}

#[test]
#[ignore = "live: just live-check"]
fn t1_in_04_live_typing() {
    let text = "Hello mrdpd 42";
    let mut lab = Lab::start();
    lab.require_focus();
    for c in text.chars() {
        let (sc, shift) = scancode(c);
        if shift {
            lab.key(SC_LSHIFT, false, true);
        }
        lab.key(sc, false, true);
        lab.key(sc, false, false);
        if shift {
            lab.key(SC_LSHIFT, false, false);
        }
    }
    let mut typed = String::new();
    while typed.chars().count() < text.chars().count() {
        let line = lab.expect_probe("keyDown", Duration::from_secs(3));
        assert_eq!(line.get("repeat"), Some("false"), "auto-repeat while typing: {line:?}");
        for hex in line.get("ch").unwrap_or("-").split(',').filter(|h| *h != "-") {
            let v = u32::from_str_radix(hex, 16).expect("hex scalar");
            typed.push(char::from_u32(v).expect("scalar"));
        }
    }
    assert_eq!(typed, text);
    println!("LIVE T1-IN-04 typing ok: {typed:?}");
}

#[test]
#[ignore = "live: just live-check"]
fn t1_in_04_live_cmd_shortcut() {
    let mut lab = Lab::start();
    lab.require_focus();
    lab.key(SC_LGUI, true, true);
    lab.key(SC_A, false, true);
    lab.key(SC_A, false, false);
    lab.key(SC_LGUI, true, false);
    let line = lab.expect_probe("keyDown", Duration::from_secs(3));
    assert_eq!(line.get("code"), Some("0"), "Cmd+A keycode: {line:?}");
    assert_eq!(line.get("cmd"), Some("true"), "Cmd flag missing: {line:?}");
    println!("LIVE T1-IN-04 Cmd+A ok");
}

#[test]
#[ignore = "live: just live-check"]
fn t1_perf_02_input_to_photon() {
    let mut lab = Lab::start();
    lab.require_focus();
    let mut samples = Vec::new();
    for i in 0..12 {
        let want = if i % 2 == 0 { Paint::Cyan } else { Paint::White };
        lab.key(SC_A, false, true);
        let t = lab.wait_paint(want, Duration::from_secs(2));
        lab.key(SC_A, false, false);
        let t = t.unwrap_or_else(|| panic!("keypress {i} never reached the screen (saw {:?})", lab.paint()));
        samples.push(t);
        while lab.next_probe(Duration::from_millis(100)).is_some() {}
    }
    samples.sort();
    let ms = |d: Duration| d.as_secs_f64() * 1000.0;
    let median = ms(samples[samples.len() / 2]);
    let max = ms(*samples.last().expect("samples"));
    println!(
        "LIVE T1-PERF-02 input-to-photon median {median:.1} ms, max {max:.1} ms over {} keys \
         ({}x{}, loopback; LAN adds network RTT)",
        samples.len(),
        lab.width,
        lab.height
    );
    assert!(median < 80.0, "T1-PERF-02: median input-to-photon {median:.1} ms ≥ 80 ms");
}

#[test]
#[ignore = "live: just live-check"]
fn t1_perf_03_idle_bitrate() {
    let mut lab = Lab::start();
    lab.idle_window(Duration::from_secs(2));
    let window = Duration::from_secs(5);
    let (bytes, _) = lab.idle_window(window);
    let kbit = bytes as f64 * 8.0 / 1000.0 / window.as_secs_f64();
    println!("LIVE T1-PERF-03 idle {kbit:.1} kbit/s ({bytes} B in {window:?}, {}x{})", lab.width, lab.height);
    assert!(kbit < 50.0, "T1-PERF-03: idle {kbit:.1} kbit/s ≥ 50");
}

#[test]
#[ignore = "live: just live-check"]
fn t1_perf_04_idle_cpu() {
    let mut lab = Lab::start();
    lab.idle_window(Duration::from_secs(2));
    let window = Duration::from_secs(5);
    let (_, cpu) = lab.idle_window(window);
    let pct = cpu / window.as_secs_f64() * 100.0;
    println!(
        "LIVE T1-PERF-04 idle CPU {pct:.1}% of one core ({cpu:.2} s over {window:?}, {}x{})",
        lab.width, lab.height
    );
    assert!(pct < 40.0, "T1-PERF-04: idle CPU {pct:.1}% ≥ 40% of one core");
}
