import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import XCTest

@testable import HostKit
import ViewportClient
import ViewportProtocol

final class RecordingPoster: EventPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [CGEvent] = []

    func post(_ event: CGEvent) { lock.withLock { events.append(event) } }

    var all: [CGEvent] { lock.withLock { events } }

    func clear() { lock.withLock { events.removeAll() } }
}

/// Collects everything a client session receives.
final class ClientRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var welcome: Welcome?
    private(set) var streams: [StreamInfo] = []
    private(set) var frames: [VideoFrame] = []
    private(set) var thumbnails: [ThumbnailPacket] = []
    private(set) var states: [ViewportConnection.State] = []

    var handlers: ViewportConnection.Handlers {
        var h = ViewportConnection.Handlers()
        h.welcome = { w in self.lock.withLock { self.welcome = w } }
        h.stream = { s in self.lock.withLock { self.streams.append(s) } }
        h.video = { f in self.lock.withLock { self.frames.append(f) } }
        h.thumbnail = { t in self.lock.withLock { self.thumbnails.append(t) } }
        h.state = { s in self.lock.withLock { self.states.append(s) } }
        return h
    }

    func snapshot<T>(_ read: (ClientRecorder) -> T) -> T { lock.withLock { read(self) } }
}

/// Polls `condition` until it returns a value or `timeout` passes.
func eventually<T>(
    _ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
    _ condition: () -> T?
) async throws -> T {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let value = condition() { return value }
        try await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("timed out waiting for \(what)", file: file, line: line)
    throw CancellationError()
}

/// Decodes one keyframe and returns the center pixel as (r, g, b).
func centerColor(of frame: VideoFrame) throws -> (r: Int, g: Int, b: Int) {
    let format = CMSampleBufferGetFormatDescription(frame.sample)!
    var session: VTDecompressionSession?
    let attrs = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as CFDictionary
    let status = VTDecompressionSessionCreate(
        allocator: nil, formatDescription: format, decoderSpecification: nil, imageBufferAttributes: attrs,
        outputCallback: nil, decompressionSessionOut: &session)
    guard status == noErr, let session else { throw NSError(domain: "decode", code: Int(status)) }
    defer { VTDecompressionSessionInvalidate(session) }
    final class Box: @unchecked Sendable { var rgb: (Int, Int, Int)? }
    let box = Box()
    VTDecompressionSessionDecodeFrame(session, sampleBuffer: frame.sample, flags: [], infoFlagsOut: nil) { _, _, image, _, _ in
        guard let image else { return }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(image)
        let p = base + (CVPixelBufferGetHeight(image) / 2) * stride + (CVPixelBufferGetWidth(image) / 2) * 4
        box.rgb = (Int(p[2]), Int(p[1]), Int(p[0]))
    }
    VTDecompressionSessionWaitForAsynchronousFrames(session)
    guard let rgb = box.rgb else { throw NSError(domain: "decode", code: -1) }
    return rgb
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mrdpd-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
