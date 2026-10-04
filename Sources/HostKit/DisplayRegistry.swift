import AppKit
import CoreGraphics
import Foundation
import ViewportProtocol

public protocol DisplayListing: Sendable {
    func displays() -> [DisplayInfo]
}

/// T1-VP-01: the Mac's active displays from CoreGraphics (no TCC needed), named by NSScreen,
/// numbered in arrangement order. Mirrored displays appear once.
public final class DisplayRegistry: DisplayListing, @unchecked Sendable {
    private let lock = NSLock()
    private var onChange: (@Sendable () -> Void)?
    private var pending: DispatchWorkItem?

    public init() {}

    public func displays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let active = ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
        var frames: [UInt32: RectD] = [:]
        for id in active {
            let b = CGDisplayBounds(id)
            frames[id] = RectD(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height)
        }
        let names = Self.screenNames()
        return ViewportGeometry.arrangementOrder(frames).enumerated().map { offset, id in
            let frame = frames[id]!
            let mode = CGDisplayCopyDisplayMode(id)
            let pixels = PixelSize(
                width: mode?.pixelWidth ?? Int(frame.width), height: mode?.pixelHeight ?? Int(frame.height))
            return DisplayInfo(
                id: id, index: offset + 1, name: names[id] ?? "Display \(offset + 1)", isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0, frame: frame, pixelSize: pixels)
        }
    }

    /// Calls `onChange` (debounced) when displays are added, removed, moved, or change mode.
    public func observe(_ onChange: @escaping @Sendable () -> Void) {
        lock.withLock { self.onChange = onChange }
        CGDisplayRegisterReconfigurationCallback(
            { _, flags, user in
                guard let user, !flags.contains(.beginConfigurationFlag) else { return }
                Unmanaged<DisplayRegistry>.fromOpaque(user).takeUnretainedValue().changed()
            }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func changed() {
        let work = DispatchWorkItem { [weak self] in
            let handler = self?.lock.withLock { self?.onChange }
            handler?()
        }
        lock.withLock {
            pending?.cancel()
            pending = work
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    static func screenNames() -> [UInt32: String] {
        let read = { () -> [UInt32: String] in
            var out: [UInt32: String] = [:]
            for screen in NSScreen.screens {
                if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    out[n.uint32Value] = screen.localizedName
                }
            }
            return out
        }
        return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
    }
}

/// A fixed display list for tests.
public struct StaticDisplayList: DisplayListing {
    public let list: [DisplayInfo]

    public init(_ list: [DisplayInfo]) { self.list = list }

    public func displays() -> [DisplayInfo] { list }
}
