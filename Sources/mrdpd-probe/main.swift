import AppKit
@preconcurrency import ScreenCaptureKit

// Lab oracle for `just live-check` (T1-IN-03, T1-IN-04, T1-PERF-02/03/04).
// Covers the captured display (first SCDisplay, same as `mrdpd-serve`) with one
// window, logs every input it receives to stdout, and paints a colour per event
// kind so the RDP client can see the photon. Mouse events repaint the whole window;
// key events toggle a small patch at the client's sample point (lower-left tenth),
// so T1-PERF-02 measures a typing-sized update, not a full-display repaint.
// Not a product type.
//
// stdout lines are `ev=<kind> key=value ...`; Quartz global points.
// Exits on stdin EOF, Escape, or after 180 s.

setvbuf(stdout, nil, _IOLBF, 0)

func emit(_ line: String) {
    print(line)
}

guard CGPreflightScreenCaptureAccess() else {
    emit("ev=error why=screen-recording-tcc")
    exit(1)
}

let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
// Default: the first SCDisplay (what `mrdpd-serve` captures). MRDPD_PROBE_DISPLAY=<id> picks another
// (the native host starts on the main display).
let wanted = ProcessInfo.processInfo.environment["MRDPD_PROBE_DISPLAY"].flatMap(UInt32.init)
guard let display = wanted.flatMap({ id in content.displays.first { $0.displayID == id } }) ?? content.displays.first,
      let screen = NSScreen.screens.first(where: {
          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
              == display.displayID
      })
else {
    emit("ev=error why=no-display")
    exit(1)
}

final class ProbeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ProbeView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

enum Paint {
    static let idle = (0.25, 0.25, 0.25)
    static let leftDown = (1.0, 0.0, 0.0)
    static let up = (0.0, 1.0, 0.0)
    static let rightDown = (1.0, 0.0, 1.0)
    static let dragged = (1.0, 1.0, 0.0)
    static let scroll = (0.0, 0.0, 1.0)
    static let keyA = (0.0, 1.0, 1.0)
    static let keyB = (1.0, 1.0, 1.0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = ProbeWindow(
    contentRect: screen.frame,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
window.isReleasedWhenClosed = false
let view = ProbeView(frame: NSRect(origin: .zero, size: screen.frame.size))
view.wantsLayer = true
window.contentView = view
window.setFrame(screen.frame, display: true)

@MainActor
func paint(_ rgb: (Double, Double, Double)) {
    let color = NSColor(
        colorSpace: screen.colorSpace ?? .deviceRGB,
        components: [rgb.0, rgb.1, rgb.2, 1],
        count: 4
    )
    view.layer?.backgroundColor = color.cgColor
    paintKeyPatch(nil)
}

// Patch centred on the sample point (x = w/10, y = 9h/10 from the top; layers are Y-up).
let keyPatch = CALayer()
keyPatch.frame = NSRect(
    x: screen.frame.width / 10 - 30,
    y: screen.frame.height / 10 - 30,
    width: 60,
    height: 60
)
keyPatch.isHidden = true
view.layer?.addSublayer(keyPatch)

@MainActor
func paintKeyPatch(_ rgb: (Double, Double, Double)?) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if let rgb {
        keyPatch.backgroundColor = NSColor(
            colorSpace: screen.colorSpace ?? .deviceRGB,
            components: [rgb.0, rgb.1, rgb.2, 1],
            count: 4
        ).cgColor
        keyPatch.isHidden = false
    } else {
        keyPatch.isHidden = true
    }
    CATransaction.commit()
}

paint(Paint.idle)

var keyDowns = 0

func fmt(_ v: CGFloat) -> String {
    String(format: "%.1f", Double(v))
}

let mask: NSEvent.EventTypeMask = [
    .leftMouseDown, .leftMouseUp, .leftMouseDragged,
    .rightMouseDown, .rightMouseUp,
    .scrollWheel, .keyDown, .keyUp,
]
_ = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
    let loc = event.cgEvent?.location ?? .zero
    let at = "x=\(fmt(loc.x)) y=\(fmt(loc.y))"
    switch event.type {
    case .leftMouseDown:
        paint(Paint.leftDown)
        emit("ev=leftDown \(at)")
    case .leftMouseUp:
        paint(Paint.up)
        emit("ev=leftUp \(at)")
    case .rightMouseDown:
        paint(Paint.rightDown)
        emit("ev=rightDown \(at)")
    case .rightMouseUp:
        paint(Paint.up)
        emit("ev=rightUp \(at)")
    case .leftMouseDragged:
        paint(Paint.dragged)
        emit("ev=leftDragged \(at)")
    case .scrollWheel:
        paint(Paint.scroll)
        emit("ev=scroll dy=\(fmt(event.scrollingDeltaY)) inverted=\(event.isDirectionInvertedFromDevice) \(at)")
    case .keyDown:
        if event.keyCode == 0x35 {
            emit("ev=escape")
            exit(2)
        }
        keyDowns += 1
        paintKeyPatch(keyDowns % 2 == 1 ? Paint.keyA : Paint.keyB)
        let ch = (event.characters ?? "").unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ",")
        let flags = event.modifierFlags
        emit(
            "ev=keyDown code=\(event.keyCode) ch=\(ch.isEmpty ? "-" : ch)"
                + " cmd=\(flags.contains(.command)) shift=\(flags.contains(.shift))"
                + " repeat=\(event.isARepeat)"
        )
    case .keyUp:
        emit("ev=keyUp code=\(event.keyCode)")
    default:
        break
    }
    return nil
}

let center = NotificationCenter.default
_ = center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
    emit("ev=key")
}
_ = center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
    emit("ev=resignKey")
}

Thread.detachNewThread {
    while readLine() != nil {}
    exit(0)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
    emit("ev=timeout")
    exit(3)
}

window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
let f = display.frame
emit("ev=ready x=\(fmt(f.origin.x)) y=\(fmt(f.origin.y)) w=\(fmt(f.width)) h=\(fmt(f.height)) id=\(display.displayID)")
app.run()
