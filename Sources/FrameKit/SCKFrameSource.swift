import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit `FrameSource` (T1-GFX-01 M4). `FrameSource` still has only `nextFrame()`.
public final class SCKFrameSource: FrameSource, @unchecked Sendable {
    public static var screenCaptureAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public let showsCursor: Bool
    public let pixelWidth: UInt32
    public let pixelHeight: UInt32
    public let pointFrame: CGRect
    private let state = DispatchQueue(label: "mrdpd.sck.state")
    private let sampleQueue = DispatchQueue(label: "mrdpd.sck.sample")
    private let output = Output()
    private var stream: SCStream?
    private var latest: Frame?
    private var waiting: CheckedContinuation<Frame, Never>?

    public init(settings: SCKSettings = SCKSettings()) async throws {
        guard Self.screenCaptureAllowed else {
            throw SCKFrameSourceError.denied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw SCKFrameSourceError.noDisplay
        }
        self.showsCursor = settings.showsCursor
        self.pixelWidth = UInt32(display.width)
        self.pixelHeight = UInt32(display.height)
        self.pointFrame = display.frame

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = settings.showsCursor
        config.queueDepth = 8
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        output.owner = self
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream

        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let ready = state.sync { latest != nil }
            if ready {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw SCKFrameSourceError.timeout
    }

    deinit {
        let stream = stream
        Task { try? await stream?.stopCapture() }
    }

    public func nextFrame() async -> Frame {
        await withCheckedContinuation { cont in
            state.sync {
                if let frame = latest {
                    latest = nil
                    cont.resume(returning: frame)
                    return
                }
                waiting = cont
            }
        }
    }

    fileprivate func handle(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }
        let dirty = Self.rects(from: sampleBuffer)
        guard let frame = CaptureFrame.make(pixelBuffer: pixelBuffer, dirty: dirty) else {
            return
        }
        state.sync {
            if let waiting {
                self.waiting = nil
                waiting.resume(returning: frame)
            } else {
                latest = frame
            }
        }
    }

    private static func rects(from sampleBuffer: CMSampleBuffer) -> [Rect] {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let first = attachments.first,
            let cgRects = first[.dirtyRects] as? [CGRect]
        else {
            return []
        }
        return cgRects.compactMap { cg -> Rect? in
            let w = cg.width.rounded(.towardZero)
            let h = cg.height.rounded(.towardZero)
            guard w > 0, h > 0 else {
                return nil
            }
            return Rect(
                x: Int32(cg.origin.x.rounded(.towardZero)),
                y: Int32(cg.origin.y.rounded(.towardZero)),
                width: UInt32(w),
                height: UInt32(h)
            )
        }
    }
}

public enum SCKFrameSourceError: Error {
    case noDisplay
    case denied
    case timeout
}

private final class Output: NSObject, SCStreamOutput {
    weak var owner: SCKFrameSource?

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else {
            return
        }
        owner?.handle(sampleBuffer)
    }
}
