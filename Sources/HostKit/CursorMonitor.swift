import AppKit
import CoreGraphics
import Foundation
import ViewportProtocol

/// T1-GFX-06: watches the Mac cursor's shape and position so native clients can draw it locally
/// (no video latency on the pointer). Polls at 30 Hz on the main queue (AppKit).
public final class CursorMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var lastHash = 0
    private var serial: UInt32 = 0
    private var shape: CursorShape?
    private var location = CGPoint.zero
    private var shapeListeners: [UUID: @Sendable (CursorShape) -> Void] = [:]
    private var locationListeners: [UUID: @Sendable (CGPoint) -> Void] = [:]

    public init() {}

    public var currentShape: CursorShape? { lock.withLock { shape } }
    public var currentLocation: CGPoint { lock.withLock { location } }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(33))
        t.setEventHandler { [weak self] in self?.poll() }
        lock.withLock { timer = t }
        t.resume()
    }

    public func subscribe(
        _ id: UUID, shape onShape: @escaping @Sendable (CursorShape) -> Void,
        location onLocation: @escaping @Sendable (CGPoint) -> Void
    ) {
        let current = lock.withLock { () -> (CursorShape?, CGPoint) in
            shapeListeners[id] = onShape
            locationListeners[id] = onLocation
            return (shape, location)
        }
        if let s = current.0 { onShape(s) }
        onLocation(current.1)
    }

    public func unsubscribe(_ id: UUID) {
        lock.withLock {
            shapeListeners[id] = nil
            locationListeners[id] = nil
        }
    }

    private func poll() {
        if let loc = CGEvent(source: nil)?.location {
            let listeners = lock.withLock { () -> [@Sendable (CGPoint) -> Void] in
                guard loc != location else { return [] }
                location = loc
                return Array(locationListeners.values)
            }
            for l in listeners { l(loc) }
        }
        guard let cursor = NSCursor.currentSystem else { return }
        let size = cursor.image.size
        var rect = CGRect(origin: .zero, size: CGSize(width: size.width * 2, height: size.height * 2))
        guard size.width > 0, let cg = cursor.image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let data = cg.dataProvider?.data as Data?
        else { return }
        var hasher = Hasher()
        hasher.combine(data)
        hasher.combine(cursor.hotSpot.x)
        hasher.combine(cursor.hotSpot.y)
        let hash = hasher.finalize()
        guard hash != lock.withLock({ lastHash }) else { return }
        guard let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        let (newShape, listeners) = lock.withLock { () -> (CursorShape, [@Sendable (CursorShape) -> Void]) in
            lastHash = hash
            serial &+= 1
            let s = CursorShape(
                serial: serial, hotspotX: cursor.hotSpot.x, hotspotY: cursor.hotSpot.y, width: size.width,
                height: size.height, png: png)
            shape = s
            return (s, Array(shapeListeners.values))
        }
        for l in listeners { l(newShape) }
    }
}
