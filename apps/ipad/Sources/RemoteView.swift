import AVFoundation
import SwiftUI
import UIKit
import ViewportClient
import ViewportProtocol

struct RemoteSurface: UIViewRepresentable {
    let model: ViewportModel

    func makeUIView(context: Context) -> RemoteView { RemoteView(model: model) }

    func updateUIView(_ view: RemoteView, context: Context) { view.setNeedsLayout() }
}

/// The Mac display: an `AVSampleBufferDisplayLayer` (hardware H.264 decode) plus every input path
/// iPadOS offers, mapped to normalized picture coordinates (T2-NAT-05):
/// - Magic Keyboard / hardware keys → HID usages (Cmd stays Cmd); Ctrl+Option shortcuts switch displays.
/// - Trackpad or mouse: hover moves, clicks (secondary = right), drags; two-finger scroll with phases
///   and momentum; the Mac cursor is drawn locally at the pointer (no video latency).
/// - Touch: tap = click, long press = right click, one-finger drag = drag, two-finger pan = scroll,
///   three-finger tap = display picker.
final class RemoteView: UIView, UIPointerInteractionDelegate {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    private var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    private let model: ViewportModel
    private let cursorLayer = CALayer()
    private var cursorPointSize = CGSize.zero
    private var cursorOnThisDisplay = true
    private var pointer: CGPoint?
    private var lastPixels: PixelSize?
    private var pressed: [ObjectIdentifier: MouseButton] = [:]
    private var momentumLink: CADisplayLink?
    private var momentumEvents: [InputEvent] = []
    private var observers: [NSObjectProtocol] = []

    init(model: ViewportModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "remoteView"
        accessibilityLabel = "Mac display"
        accessibilityTraits = [.allowsDirectInteraction]
        displayLayer.videoGravity = .resizeAspect
        model.video.attach(displayLayer)

        cursorLayer.zPosition = 100
        cursorLayer.isHidden = true
        cursorLayer.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "hidden": NSNull()]
        layer.addSublayer(cursorLayer)
        model.cursorChanged = { [weak self] update in self?.apply(update) }
        accessibilityValue = "connecting"
        model.displayLabelChanged = { [weak self] label in self?.accessibilityValue = label }

        addInteraction(UIPointerInteraction(delegate: self))
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))

        let wheel = UIPanGestureRecognizer(target: self, action: #selector(scroll(_:)))
        wheel.allowedScrollTypesMask = .all
        wheel.allowedTouchTypes = []
        addGestureRecognizer(wheel)

        let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        tap.allowedTouchTypes = direct
        addGestureRecognizer(tap)
        let threeFingerTap = UITapGestureRecognizer(target: self, action: #selector(threeFingerTap(_:)))
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.allowedTouchTypes = direct
        addGestureRecognizer(threeFingerTap)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        longPress.allowedTouchTypes = direct
        addGestureRecognizer(longPress)
        let drag = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        drag.allowedTouchTypes = direct
        drag.maximumNumberOfTouches = 1
        addGestureRecognizer(drag)
        let twoFinger = UIPanGestureRecognizer(target: self, action: #selector(touchScroll(_:)))
        twoFinger.allowedTouchTypes = direct
        twoFinger.minimumNumberOfTouches = 2
        twoFinger.maximumNumberOfTouches = 2
        addGestureRecognizer(twoFinger)

        registerForTraitChanges([UITraitDisplayScale.self]) { (view: RemoteView, _) in view.setNeedsLayout() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: geometry

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        let pixels = PixelSize(width: Int((bounds.width * scale).rounded()), height: Int((bounds.height * scale).rounded()))
        if pixels.width > 0, pixels.height > 0, pixels != lastPixels {
            lastPixels = pixels
            model.viewportChanged(pixels)
        }
        placeCursor()
    }

    private var pictureRect: CGRect {
        let content = model.contentSize
        guard content.width > 0, content.height > 0 else { return bounds }
        return AVMakeRect(aspectRatio: content, insideRect: bounds)
    }

    private func normalized(_ p: CGPoint) -> Point01 {
        let r = pictureRect
        return ViewportGeometry.normalized(
            viewX: p.x, viewY: p.y, pictureRect: RectD(x: r.minX, y: r.minY, width: r.width, height: r.height))
    }

    // MARK: focus

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        guard let window else { return }
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: UIWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.setFocused(true)
                    _ = self?.becomeFirstResponder()
                }
            })
        observers.append(
            center.addObserver(forName: UIWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.setFocused(false) }
            })
        DispatchQueue.main.async { [weak self] in _ = self?.becomeFirstResponder() }
    }

    // MARK: keyboard

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = forward(presses, down: true)
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = forward(presses, down: false)
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = forward(presses, down: false)
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }

    private func forward(_ presses: Set<UIPress>, down: Bool) -> Set<UIPress> {
        var rest = Set<UIPress>()
        for press in presses {
            if let key = press.key {
                model.key(usage: UInt16(truncatingIfNeeded: key.keyCode.rawValue), down: down)
            } else {
                rest.insert(press)
            }
        }
        return rest
    }

    // MARK: trackpad and mouse

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        cursorLayer.contents == nil ? nil : .hidden()
    }

    @objc private func hover(_ g: UIHoverGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began, .changed:
            pointer = p
            placeCursor()
            model.send(.move(normalized(p)))
            if p.y < 16, abs(p.x - bounds.midX) < 240 { model.revealHUD() }
        case .ended, .cancelled:
            pointer = nil
            placeCursor()
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where touch.type == .indirectPointer {
            let p = touch.location(in: self)
            let button: MouseButton = (event?.buttonMask.contains(.secondary) ?? false) ? .right : .left
            pressed[ObjectIdentifier(touch)] = button
            pointer = p
            placeCursor()
            model.send(.button(button, down: true, at: normalized(p), clickCount: max(1, touch.tapCount)))
        }
        _ = becomeFirstResponder()
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where touch.type == .indirectPointer {
            let p = touch.location(in: self)
            pointer = p
            placeCursor()
            model.send(.move(normalized(p)))
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
        super.touchesCancelled(touches, with: event)
    }

    private func release(_ touches: Set<UITouch>) {
        for touch in touches where touch.type == .indirectPointer {
            guard let button = pressed.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            model.send(.button(button, down: false, at: normalized(touch.location(in: self)), clickCount: max(1, touch.tapCount)))
        }
    }

    @objc private func scroll(_ g: UIPanGestureRecognizer) {
        scrollGesture(g, moveFirst: false)
    }

    // MARK: touch

    @objc private func tap(_ g: UITapGestureRecognizer) {
        let at = normalized(g.location(in: self))
        model.send(.move(at))
        model.send(.button(.left, down: true, at: at, clickCount: 1))
        model.send(.button(.left, down: false, at: at, clickCount: 1))
        _ = becomeFirstResponder()
    }

    @objc private func threeFingerTap(_ g: UITapGestureRecognizer) {
        model.perform(.picker)
    }

    @objc private func longPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let at = normalized(g.location(in: self))
        model.send(.move(at))
        model.send(.button(.right, down: true, at: at, clickCount: 1))
        model.send(.button(.right, down: false, at: at, clickCount: 1))
    }

    @objc private func drag(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began:
            let t = g.translation(in: self)
            let start = normalized(CGPoint(x: p.x - t.x, y: p.y - t.y))
            model.send(.move(start))
            model.send(.button(.left, down: true, at: start, clickCount: 1))
            model.send(.move(normalized(p)))
        case .changed:
            model.send(.move(normalized(p)))
        case .ended, .cancelled, .failed:
            model.send(.button(.left, down: false, at: normalized(p), clickCount: 1))
        default:
            break
        }
    }

    @objc private func touchScroll(_ g: UIPanGestureRecognizer) {
        scrollGesture(g, moveFirst: true)
    }

    // MARK: scrolling with phases and momentum

    private func scrollGesture(_ g: UIPanGestureRecognizer, moveFirst: Bool) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        switch g.state {
        case .began:
            stopMomentum()
            if moveFirst { model.send(.move(normalized(g.location(in: self)))) }
            model.send(.scroll(dx: t.x, dy: t.y, phase: .began, momentum: .none))
        case .changed:
            model.send(.scroll(dx: t.x, dy: t.y, phase: .changed, momentum: .none))
        case .ended:
            model.send(.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none))
            startMomentum(g.velocity(in: self))
        case .cancelled, .failed:
            model.send(.scroll(dx: 0, dy: 0, phase: .cancelled, momentum: .none))
        default:
            break
        }
    }

    private func startMomentum(_ velocity: CGPoint) {
        momentumEvents = MomentumScroller.events(velocityX: velocity.x, velocityY: velocity.y)
        guard !momentumEvents.isEmpty else { return }
        let link = CADisplayLink(target: self, selector: #selector(momentumTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        momentumLink = link
    }

    @objc private func momentumTick() {
        guard !momentumEvents.isEmpty else {
            stopMomentum()
            return
        }
        model.send(momentumEvents.removeFirst())
    }

    private func stopMomentum() {
        if momentumLink != nil, !momentumEvents.isEmpty {
            model.send(.scroll(dx: 0, dy: 0, phase: .none, momentum: .end))
        }
        momentumLink?.invalidate()
        momentumLink = nil
        momentumEvents = []
    }

    // MARK: cursor (T1-GFX-06)

    private func apply(_ update: CursorUpdate) {
        switch update {
        case .shape(let image, let hotspot, let size):
            cursorLayer.contents = image.cgImage
            cursorPointSize = size
            cursorLayer.anchorPoint = CGPoint(
                x: size.width > 0 ? hotspot.x / size.width : 0, y: size.height > 0 ? hotspot.y / size.height : 0)
        case .visible(let visible):
            cursorOnThisDisplay = visible
        }
        placeCursor()
    }

    private func placeCursor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let p = pointer, cursorOnThisDisplay, cursorLayer.contents != nil else {
            cursorLayer.isHidden = true
            return
        }
        // Mac points → this window's points, at the scale the picture is drawn.
        var scale: CGFloat = 1
        if let display = model.currentDisplay, display.frame.width > 0 {
            scale = min(2, max(0.5, pictureRect.width / display.frame.width))
        }
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: cursorPointSize.width * scale, height: cursorPointSize.height * scale)
        cursorLayer.position = p
        cursorLayer.isHidden = false
    }
}
