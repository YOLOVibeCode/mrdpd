import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import ViewportProtocol

public struct CapturedFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    /// Host monotonic time of capture.
    public let hostNanos: UInt64

    public init(pixelBuffer: CVPixelBuffer, hostNanos: UInt64) {
        self.pixelBuffer = pixelBuffer
        self.hostNanos = hostNanos
    }
}

public struct CaptureTarget: Equatable, Sendable {
    public var displayID: UInt32
    /// Output size; the source display is scaled into it on the GPU (aspect preserved).
    public var size: PixelSize
    public var fps: Int

    public init(displayID: UInt32, size: PixelSize, fps: Int) {
        self.displayID = displayID
        self.size = size
        self.fps = fps
    }
}

/// One live picture of one display at one size (T1-VP-01/02). `apply` starts or retargets it.
public protocol CaptureStream: AnyObject, Sendable {
    func apply(_ target: CaptureTarget) async throws
    func stop() async
}

public protocol CaptureFactory: Sendable {
    func makeStream(onFrame: @escaping @Sendable (CapturedFrame) -> Void) -> CaptureStream
}

public enum CaptureError: Error {
    case displayNotFound(UInt32)
}

/// ScreenCaptureKit: NV12 (BT.709) at the viewport's size, straight into VideoToolbox, no copies.
/// Needs Screen Recording TCC.
public struct SCKCaptureFactory: CaptureFactory {
    public let showsCursor: Bool

    public init(showsCursor: Bool) { self.showsCursor = showsCursor }

    public func makeStream(onFrame: @escaping @Sendable (CapturedFrame) -> Void) -> CaptureStream {
        SCKCaptureStream(showsCursor: showsCursor, onFrame: onFrame)
    }
}

final class SCKCaptureStream: NSObject, CaptureStream, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let showsCursor: Bool
    private let onFrame: @Sendable (CapturedFrame) -> Void
    private let queue = DispatchQueue(label: "mrdpd.capture", qos: .userInteractive)
    private let lock = NSLock()
    private var stream: SCStream?
    private var current: CaptureTarget?

    init(showsCursor: Bool, onFrame: @escaping @Sendable (CapturedFrame) -> Void) {
        self.showsCursor = showsCursor
        self.onFrame = onFrame
    }

    func apply(_ target: CaptureTarget) async throws {
        let config = configuration(target)
        let (existing, old) = lock.withLock { (stream, current) }
        if let existing {
            if old?.displayID != target.displayID {
                try await existing.updateContentFilter(try await Self.filter(target.displayID))
            }
            try await existing.updateConfiguration(config)
        } else {
            let stream = SCStream(filter: try await Self.filter(target.displayID), configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            lock.withLock { self.stream = stream }
        }
        lock.withLock { current = target }
    }

    func stop() async {
        let s = lock.withLock { () -> SCStream? in
            defer { stream = nil }
            return stream
        }
        try? await s?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer), let pb = sampleBuffer.imageBuffer else {
            return
        }
        onFrame(CapturedFrame(pixelBuffer: pb, hostNanos: DispatchTime.now().uptimeNanoseconds))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write(Data("mrdpd-host: capture stopped: \(error)\n".utf8))
    }

    private func configuration(_ t: CaptureTarget) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.width = t.size.width
        c.height = t.size.height
        c.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        c.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        c.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, t.fps)))
        c.queueDepth = 5
        c.showsCursor = showsCursor
        c.scalesToFit = true
        c.preservesAspectRatio = true
        c.capturesAudio = false
        return c
    }

    private static func filter(_ displayID: UInt32) async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound(displayID)
        }
        return SCContentFilter(display: display, excludingWindows: [])
    }

    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }
}

/// TCC-free capture for tests: solid NV12 frames whose color depends on the display, ~20 fps.
public struct SyntheticCaptureFactory: CaptureFactory {
    /// BT.709 video-range (Y, Cb, Cr) per display.
    public let colors: [UInt32: (y: UInt8, cb: UInt8, cr: UInt8)]

    public init(colors: [UInt32: (y: UInt8, cb: UInt8, cr: UInt8)]) { self.colors = colors }

    public func makeStream(onFrame: @escaping @Sendable (CapturedFrame) -> Void) -> CaptureStream {
        SyntheticCaptureStream(colors: colors, onFrame: onFrame)
    }

    /// Video-range BT.709 for an 8-bit sRGB-ish color.
    public static func ycbcr(r: Double, g: Double, b: Double) -> (y: UInt8, cb: UInt8, cr: UInt8) {
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let cb = (b - y) / 1.8556
        let cr = (r - y) / 1.5748
        func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        return (q(16 + 219 * y / 255), q(128 + 224 * cb / 255), q(128 + 224 * cr / 255))
    }
}

final class SyntheticCaptureStream: CaptureStream, @unchecked Sendable {
    private let colors: [UInt32: (y: UInt8, cb: UInt8, cr: UInt8)]
    private let onFrame: @Sendable (CapturedFrame) -> Void
    private let queue = DispatchQueue(label: "mrdpd.synthetic")
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var target: CaptureTarget?

    init(colors: [UInt32: (y: UInt8, cb: UInt8, cr: UInt8)], onFrame: @escaping @Sendable (CapturedFrame) -> Void) {
        self.colors = colors
        self.onFrame = onFrame
    }

    func apply(_ target: CaptureTarget) async throws {
        guard colors[target.displayID] != nil else { throw CaptureError.displayNotFound(target.displayID) }
        lock.withLock { self.target = target }
        let needsTimer = lock.withLock { timer == nil }
        if needsTimer {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(50))
            t.setEventHandler { [weak self] in self?.emit() }
            lock.withLock { timer = t }
            t.resume()
        }
    }

    func stop() async {
        lock.withLock {
            timer?.cancel()
            timer = nil
        }
    }

    private func emit() {
        guard let target = lock.withLock({ target }), let color = colors[target.displayID],
              let pb = Self.solidNV12(size: target.size, color: color)
        else { return }
        onFrame(CapturedFrame(pixelBuffer: pb, hostNanos: DispatchTime.now().uptimeNanoseconds))
    }

    static func solidNV12(size: PixelSize, color: (y: UInt8, cb: UInt8, cr: UInt8)) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        guard
            CVPixelBufferCreate(
                nil, size.width, size.height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attrs as CFDictionary, &pb)
                == kCVReturnSuccess, let pb
        else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        for row in 0..<size.height { memset(yBase + row * yStride, Int32(color.y), size.width) }
        let cBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!.assumingMemoryBound(to: UInt8.self)
        let cStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        for row in 0..<(size.height / 2) {
            let line = cBase + row * cStride
            for col in 0..<(size.width / 2) {
                line[col * 2] = color.cb
                line[col * 2 + 1] = color.cr
            }
        }
        return pb
    }
}
