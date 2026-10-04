import CoreVideo
import Foundation
import ViewportProtocol
import ViewportTransport

/// Capture → encode → send for one viewport, outside any actor (no hop per frame).
///
/// Latency first: at most one frame inside the encoder, at most `maxPendingSends` frames waiting
/// for the network. Frames that arrive while either is busy are not queued; only the newest is kept
/// and encoded as soon as there is room, so a burst never builds lag and the final picture always
/// arrives even though ScreenCaptureKit only delivers frames when something changes.
final class VideoPipeline: @unchecked Sendable {
    static let maxPendingSends = 2

    private let connection: FramedConnection
    private let lock = NSLock()
    private var encoder: H264Encoder?
    private var epoch: UInt32 = 0
    private var size = PixelSize(width: 0, height: 0)
    private var accepting = false
    private var latest: CapturedFrame?
    private var latestEncoded = true
    private var forceKeyframe = true
    private var inFlight = false
    private var timer: DispatchSourceTimer?

    init(connection: FramedConnection) {
        self.connection = connection
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "mrdpd.pipeline.tick"))
        t.schedule(deadline: .now() + .milliseconds(30), repeating: .milliseconds(30))
        t.setEventHandler { [weak self] in self?.pump() }
        timer = t
        t.resume()
    }

    /// New encoder for a new epoch. Frames are ignored until `accept()` (the capture is retargeting).
    func configure(encoder: H264Encoder?, epoch: UInt32, size: PixelSize) {
        let old = lock.withLock { () -> H264Encoder? in
            let old = self.encoder
            self.encoder = encoder
            self.epoch = epoch
            self.size = size
            accepting = false
            latest = nil
            latestEncoded = true
            forceKeyframe = true
            inFlight = false
            return old
        }
        old?.invalidate()
    }

    func accept() {
        lock.withLock { accepting = true }
    }

    func setFrameRate(_ fps: Int) {
        lock.withLock { encoder }?.setFrameRate(fps)
    }

    /// Next encode is a keyframe; re-encode the last picture now if the screen is idle.
    func requestKeyframe() {
        lock.withLock {
            forceKeyframe = true
            if latest != nil { latestEncoded = false }
        }
        pump()
    }

    func submit(_ frame: CapturedFrame) {
        let taken = lock.withLock { () -> Bool in
            guard accepting, CVPixelBufferGetWidth(frame.pixelBuffer) == size.width,
                  CVPixelBufferGetHeight(frame.pixelBuffer) == size.height
            else { return false }
            latest = frame
            latestEncoded = false
            return true
        }
        if taken { pump() }
    }

    func stop() {
        timer?.cancel()
        configure(encoder: nil, epoch: 0, size: PixelSize(width: 0, height: 0))
    }

    private func pump() {
        let job = lock.withLock { () -> (H264Encoder, CapturedFrame, Bool, UInt32, PixelSize)? in
            guard let encoder, let latest, !latestEncoded, !inFlight,
                  connection.pendingSends <= Self.maxPendingSends
            else { return nil }
            latestEncoded = true
            inFlight = true
            defer { forceKeyframe = false }
            return (encoder, latest, forceKeyframe, epoch, size)
        }
        guard let (encoder, frame, force, epoch, size) = job else { return }
        encoder.encode(frame.pixelBuffer, hostNanos: frame.hostNanos, forceKeyframe: force) { [weak self] encoded in
            self?.finished(encoded, epoch: epoch, size: size, forced: force)
        }
    }

    private func finished(_ encoded: EncodedFrame?, epoch: UInt32, size: PixelSize, forced: Bool) {
        let current = lock.withLock { () -> Bool in
            guard epoch == self.epoch else { return false }
            inFlight = false
            if encoded == nil {
                // Dropped by the encoder: retry from the newest picture on the next tick.
                latestEncoded = false
                if forced { forceKeyframe = true }
            }
            return true
        }
        guard current, let encoded else { return }
        let packet = VideoPacket(
            epoch: epoch, isKeyframe: encoded.isKeyframe, captureTimeNanos: encoded.hostNanos, width: UInt32(size.width),
            height: UInt32(size.height), parameterSets: encoded.parameterSets, avcc: encoded.avcc)
        connection.send(packet.frame()) { [weak self] _ in self?.pump() }
        pump()
    }
}
