import AppKit
import CoreGraphics
import Foundation
import InputKit
import ViewportProtocol

public protocol EventPosting: Sendable {
    func post(_ event: CGEvent)
}

/// Drops events: view-only hosting, and app UI tests that must not drive the real Mac.
public struct NullEventPoster: EventPosting {
    public init() {}

    public func post(_ event: CGEvent) {}
}

/// Posts to the HID event tap (needs Accessibility TCC).
public struct HIDEventPoster: EventPosting {
    public init() {}

    public func post(_ event: CGEvent) { event.post(tap: .cghidEventTap) }
}

/// T2-NAT-05: native-client input → CGEvents. Mac-correct modifiers (left/right device bits),
/// host-side key repeat at the Mac's own settings, click counts, continuous scrolling with phases.
public final class NativeInputInjector: @unchecked Sendable {
    private let poster: EventPosting
    private let repeatDelay: TimeInterval
    private let repeatInterval: TimeInterval
    private let lock = NSLock()
    private var modifiers: Set<UInt16> = []
    private var capsLock = false
    private var heldKeys: [UInt16: UInt16] = [:]
    private var buttons: Set<MouseButton> = []
    private var location = CGPoint.zero
    private var scrollRemainder = (x: 0.0, y: 0.0)
    private var repeatTimer: DispatchSourceTimer?
    private let repeatQueue = DispatchQueue(label: "mrdpd.keyrepeat")

    public init(
        poster: EventPosting = HIDEventPoster(), repeatDelay: TimeInterval = NSEvent.keyRepeatDelay,
        repeatInterval: TimeInterval = NSEvent.keyRepeatInterval
    ) {
        self.poster = poster
        self.repeatDelay = repeatDelay
        self.repeatInterval = max(repeatInterval, 0.015)
    }

    /// `displayFrame`: the viewport's source display, Quartz global points.
    public func inject(_ event: ViewportProtocol.InputEvent, displayFrame: RectD) {
        switch event {
        case .key(let usage, let down):
            key(usage, down: down)
        case .move(let p):
            move(to: point(p, displayFrame))
        case .button(let b, let down, let p, let clicks):
            button(b, down: down, at: point(p, displayFrame), clicks: clicks)
        case .scroll(let dx, let dy, let phase, let momentum):
            scroll(dx: dx, dy: dy, phase: phase, momentum: momentum)
        case .wheel(let dx, let dy):
            wheel(dx: dx, dy: dy)
        case .releaseAll:
            releaseAll()
        }
    }

    public func releaseAll() {
        let (keys, mods, held, at) = lock.withLock { () -> ([(UInt16, UInt16)], [UInt16], Set<MouseButton>, CGPoint) in
            stopRepeat()
            defer {
                heldKeys = [:]
                modifiers = []
                buttons = []
            }
            return (heldKeys.map { ($0.key, $0.value) }, Array(modifiers), buttons, location)
        }
        for (_, code) in keys { postKey(code, down: false, flags: []) }
        for usage in mods {
            if let code = HidKeymap.virtualKeyCode(usage: usage) { postKey(code, down: false, flags: []) }
        }
        for b in held { postButton(b, down: false, at: at, clicks: 1, flags: []) }
    }

    // MARK: keys

    private func key(_ usage: UInt16, down: Bool) {
        guard let code = HidKeymap.virtualKeyCode(usage: usage) else { return }
        if usage == 0x39 {  // Caps Lock toggles on press
            let flags = lock.withLock { () -> CGEventFlags in
                if down { capsLock.toggle() }
                return currentFlags()
            }
            postKey(code, down: down, flags: flags)
            return
        }
        if HidKeymap.modifierFlags(usage: usage) != nil {
            let flags = lock.withLock { () -> CGEventFlags in
                if down { modifiers.insert(usage) } else { modifiers.remove(usage) }
                return currentFlags()
            }
            postKey(code, down: down, flags: flags)
            return
        }
        let flags = lock.withLock { () -> CGEventFlags in
            if down { heldKeys[usage] = code } else { heldKeys[usage] = nil }
            return currentFlags().union(HidKeymap.intrinsicFlags(usage: usage))
        }
        postKey(code, down: down, flags: flags)
        if down { startRepeat(usage: usage, code: code) } else { lock.withLock { stopRepeat(ifUsage: usage) } }
    }

    private var repeatingUsage: UInt16?

    private func startRepeat(usage: UInt16, code: UInt16) {
        let timer = DispatchSource.makeTimerSource(queue: repeatQueue)
        timer.schedule(deadline: .now() + repeatDelay, repeating: repeatInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let flags: CGEventFlags? = self.lock.withLock {
                guard self.heldKeys[usage] != nil else { return nil }
                return self.currentFlags().union(HidKeymap.intrinsicFlags(usage: usage))
            }
            guard let flags else { return }
            self.postKey(code, down: true, flags: flags, autorepeat: true)
        }
        lock.withLock {
            stopRepeat()
            repeatTimer = timer
            repeatingUsage = usage
        }
        timer.resume()
    }

    /// Caller holds `lock`.
    private func stopRepeat(ifUsage usage: UInt16? = nil) {
        guard usage == nil || usage == repeatingUsage else { return }
        repeatTimer?.cancel()
        repeatTimer = nil
        repeatingUsage = nil
    }

    /// Caller holds `lock`.
    private func currentFlags() -> CGEventFlags {
        var flags: CGEventFlags = capsLock ? .maskAlphaShift : []
        for usage in modifiers { if let f = HidKeymap.modifierFlags(usage: usage) { flags.formUnion(f) } }
        return flags
    }

    private func postKey(_ code: UInt16, down: Bool, flags: CGEventFlags, autorepeat: Bool = false) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        e.flags = flags
        if autorepeat { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        poster.post(e)
    }

    // MARK: pointer

    private func point(_ p: Point01, _ frame: RectD) -> CGPoint {
        let g = ViewportGeometry.globalPoint(p, displayFrame: frame)
        return CGPoint(x: g.x, y: g.y)
    }

    private func move(to p: CGPoint) {
        let (held, flags) = lock.withLock { () -> (Set<MouseButton>, CGEventFlags) in
            location = p
            return (buttons, currentFlags())
        }
        let (type, button): (CGEventType, CGMouseButton) =
            held.contains(.left) ? (.leftMouseDragged, .left)
            : held.contains(.right) ? (.rightMouseDragged, .right)
            : held.contains(.middle) ? (.otherMouseDragged, .center) : (.mouseMoved, .left)
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        e.flags = flags
        poster.post(e)
    }

    private func button(_ b: MouseButton, down: Bool, at p: CGPoint, clicks: Int) {
        let flags = lock.withLock { () -> CGEventFlags in
            location = p
            if down { buttons.insert(b) } else { buttons.remove(b) }
            return currentFlags()
        }
        postButton(b, down: down, at: p, clicks: clicks, flags: flags)
    }

    private func postButton(_ b: MouseButton, down: Bool, at p: CGPoint, clicks: Int, flags: CGEventFlags) {
        let (type, button): (CGEventType, CGMouseButton)
        switch b {
        case .left: (type, button) = (down ? .leftMouseDown : .leftMouseUp, .left)
        case .right: (type, button) = (down ? .rightMouseDown : .rightMouseUp, .right)
        case .middle: (type, button) = (down ? .otherMouseDown : .otherMouseUp, .center)
        }
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(max(1, clicks)))
        e.flags = flags
        poster.post(e)
    }

    // MARK: scrolling

    private func scroll(dx: Double, dy: Double, phase: ScrollPhase, momentum: MomentumPhase) {
        let (ix, iy, at, flags) = lock.withLock { () -> (Int32, Int32, CGPoint, CGEventFlags) in
            let tx = dx + scrollRemainder.x
            let ty = dy + scrollRemainder.y
            let ix = Int32(tx.rounded(.towardZero))
            let iy = Int32(ty.rounded(.towardZero))
            scrollRemainder = (tx - Double(ix), ty - Double(iy))
            if phase == .ended || phase == .cancelled || momentum == .end { scrollRemainder = (0, 0) }
            return (ix, iy, location, currentFlags())
        }
        guard
            let e = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: iy, wheel2: ix, wheel3: 0)
        else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
        e.location = at
        e.flags = flags
        poster.post(e)
    }

    private func wheel(dx: Int, dy: Int) {
        let (at, flags) = lock.withLock { (location, currentFlags()) }
        guard
            let e = CGEvent(
                scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)
        else { return }
        e.location = at
        e.flags = flags
        poster.post(e)
    }
}
