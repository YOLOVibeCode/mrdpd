import CoreGraphics
import Foundation
import XCTest

@testable import HostKit
import ViewportClient
import ViewportProtocol
import ViewportTransport

/// T2-NAT-01/02, T1-VP-01/02/03 end to end over loopback, TCC-free: real TLS-PSK, real
/// VideoToolbox H.264, synthetic capture (red = built-in, blue = top Sceptre), recorded input.
final class NativeLoopbackTests: XCTestCase {
    let displays = [
        DisplayInfo(
            id: 5, index: 1, name: "Sceptre Z27 (1)", isBuiltin: false, isMain: false,
            frame: RectD(x: -629, y: -2160, width: 1600, height: 1200), pixelSize: PixelSize(width: 3200, height: 2400)),
        DisplayInfo(
            id: 1, index: 2, name: "Built-in Retina Display", isBuiltin: true, isMain: true,
            frame: RectD(x: 0, y: 0, width: 1728, height: 1117), pixelSize: PixelSize(width: 3456, height: 2234)),
    ]

    func makeServer(store: PairingStore, poster: RecordingPoster) -> NativeServer {
        let env = HostEnvironment(
            hostName: "Test Mac", hostID: "host-1", displays: StaticDisplayList(displays),
            capture: SyntheticCaptureFactory(colors: [
                1: SyntheticCaptureFactory.ycbcr(r: 220, g: 20, b: 20),
                5: SyntheticCaptureFactory.ycbcr(r: 20, g: 20, b: 220),
            ]),
            makeEncoder: { try H264Encoder(size: $0, fps: $1, allowSoftware: true) },
            injector: NativeInputInjector(poster: poster, repeatDelay: 10, repeatInterval: 10),
            thumbnails: StaticThumbnailProvider(), cursor: nil, scheduler: EncodeScheduler(engines: 2), log: { _ in })
        return NativeServer(bindHost: "127.0.0.1", port: 0, store: store, environment: env)
    }

    func testPairedClientSeesMainDisplaySwitchesAndClicks() async throws {
        let store = PairingStore(directory: temporaryDirectory())
        let device = try store.pair(name: "test iPad")
        let poster = RecordingPoster()
        let server = makeServer(store: store, poster: poster)
        let port = try await server.start()
        defer { server.stop() }

        let recorder = ClientRecorder()
        let client = ViewportConnection(
            host: "127.0.0.1", port: port, deviceID: device.id, key: device.key,
            hello: Hello(clientName: "test iPad", viewport: PixelSize(width: 1376, height: 1032)), handlers: recorder.handlers)
        client.start()
        defer { client.cancel() }

        let welcome = try await eventually("welcome") { recorder.snapshot { $0.welcome } }
        XCTAssertEqual(welcome.displays.map(\.id), [5, 1])
        XCTAssertEqual(welcome.hostName, "Test Mac")

        // Main display first, sized to the client and its own aspect (T1-VP-02).
        let first = try await eventually("first keyframe") {
            recorder.snapshot { r in r.frames.first { $0.isKeyframe } }
        }
        let firstStream = try XCTUnwrap(recorder.snapshot { $0.streams.first })
        XCTAssertEqual(firstStream.displayID, 1)
        XCTAssertEqual(firstStream.contentSize.width, 1376)
        XCTAssertEqual(Double(firstStream.contentSize.width) / Double(firstStream.contentSize.height), 3456.0 / 2234.0, accuracy: 0.01)
        let red = try centerColor(of: first)
        XCTAssertGreaterThan(red.r, 150)
        XCTAssertLessThan(red.b, 80)

        // Switch to the top Sceptre (T1-VP-03): new epoch, blue, 4:3.
        client.send(.subscribe(displayID: 5))
        let switched = try await eventually("keyframe after switch") {
            recorder.snapshot { r in r.frames.first { $0.isKeyframe && $0.epoch > first.epoch } }
        }
        let blue = try centerColor(of: switched)
        XCTAssertGreaterThan(blue.b, 150)
        XCTAssertLessThan(blue.r, 80)
        XCTAssertEqual(switched.width * 3, switched.height * 4)

        // A click in the middle of the picture lands in the middle of that display (T1-VP-02).
        client.send(.input(.button(.left, down: true, at: Point01(x: 0.5, y: 0.5), clickCount: 1)))
        client.send(.input(.button(.left, down: false, at: Point01(x: 0.5, y: 0.5), clickCount: 1)))
        let down = try await eventually("mouse down") { poster.all.first { $0.type == .leftMouseDown } }
        XCTAssertEqual(down.location, CGPoint(x: 171, y: -1560))

        // Thumbnails for the picker (T2-NAT-04).
        client.send(.requestThumbnails(maxWidth: 160))
        let thumbs = try await eventually("thumbnails") {
            recorder.snapshot { r in r.thumbnails.count >= 2 ? r.thumbnails : nil }
        }
        XCTAssertEqual(Set(thumbs.map(\.displayID)), [1, 5])

        // Resize keeps the display, opens a new epoch at the new size.
        client.send(.resize(PixelSize(width: 2752, height: 2064)))
        let resized = try await eventually("stream after resize") {
            recorder.snapshot { r in r.streams.last { $0.contentSize.width == 2752 } }
        }
        XCTAssertEqual(resized.displayID, 5)
    }

    /// T1-VP-05: the owner's scenario — two windows (iPad screen, external 4K) at once, each on its own display.
    func testTwoWindowsShowDifferentDisplaysAtOnce() async throws {
        let store = PairingStore(directory: temporaryDirectory())
        let device = try store.pair(name: "iPad Pro")
        let server = makeServer(store: store, poster: RecordingPoster())
        let port = try await server.start()
        defer { server.stop() }

        let ipadScreen = ClientRecorder()
        let external4K = ClientRecorder()
        let a = ViewportConnection(
            host: "127.0.0.1", port: port, deviceID: device.id, key: device.key,
            hello: Hello(clientName: "iPad screen", viewport: PixelSize(width: 2752, height: 2064), preferredDisplayID: 1),
            handlers: ipadScreen.handlers)
        let b = ViewportConnection(
            host: "127.0.0.1", port: port, deviceID: device.id, key: device.key,
            hello: Hello(clientName: "4K monitor", viewport: PixelSize(width: 3840, height: 2160), preferredDisplayID: 5),
            handlers: external4K.handlers)
        a.start()
        b.start()
        defer {
            a.cancel()
            b.cancel()
        }
        let redFrame = try await eventually("iPad window keyframe") { ipadScreen.snapshot { r in r.frames.first { $0.isKeyframe } } }
        let blueFrame = try await eventually("4K window keyframe") { external4K.snapshot { r in r.frames.first { $0.isKeyframe } } }
        XCTAssertGreaterThan(try centerColor(of: redFrame).r, 150)
        XCTAssertGreaterThan(try centerColor(of: blueFrame).b, 150)
        XCTAssertEqual(server.sessionCount, 2)
        // 4:3 Sceptre fitted into 16:9 4K, capped for 60 fps; the iPad window gets the built-in at its width.
        let bStream = try XCTUnwrap(external4K.snapshot { $0.streams.first })
        XCTAssertLessThanOrEqual(bStream.contentSize.pixels, ViewportGeometry.maxPixelsAt60fps)
        XCTAssertEqual(bStream.contentSize.width * 3, bStream.contentSize.height * 4)

        // Switching one window leaves the other alone (T1-VP-03).
        b.send(.subscribe(displayID: 1))
        let bSwitched = try await eventually("4K window switched") {
            external4K.snapshot { r in r.frames.first { $0.isKeyframe && $0.epoch > blueFrame.epoch } }
        }
        XCTAssertGreaterThan(try centerColor(of: bSwitched).r, 150)
        XCTAssertEqual(ipadScreen.snapshot { $0.streams.count }, 1)
    }

    func testIdleScreenStillAnswersAKeyframeRequest() async throws {
        let store = PairingStore(directory: temporaryDirectory())
        let device = try store.pair(name: "test iPad")
        let server = makeServer(store: store, poster: RecordingPoster())
        let port = try await server.start()
        defer { server.stop() }
        let recorder = ClientRecorder()
        let client = ViewportConnection(
            host: "127.0.0.1", port: port, deviceID: device.id, key: device.key,
            hello: Hello(clientName: "t", viewport: PixelSize(width: 640, height: 480)), handlers: recorder.handlers)
        client.start()
        defer { client.cancel() }
        _ = try await eventually("first keyframe") { recorder.snapshot { r in r.frames.first { $0.isKeyframe } } }
        let before = recorder.snapshot { r in r.frames.filter(\.isKeyframe).count }
        client.send(.requestKeyframe)
        _ = try await eventually("second keyframe") {
            recorder.snapshot { r in r.frames.filter(\.isKeyframe).count > before ? true : nil }
        }
    }

    func testUnpairedKeyIsRefused() async throws {
        let store = PairingStore(directory: temporaryDirectory())
        let device = try store.pair(name: "real iPad")
        let server = makeServer(store: store, poster: RecordingPoster())
        let port = try await server.start()
        defer { server.stop() }
        let recorder = ClientRecorder()
        let client = ViewportConnection(
            host: "127.0.0.1", port: port, deviceID: device.id, key: Data(repeating: 1, count: 32),
            hello: Hello(clientName: "imposter", viewport: PixelSize(width: 640, height: 480)), handlers: recorder.handlers)
        client.start()
        _ = try await eventually("refused") {
            recorder.snapshot { r in r.states.contains { if case .closed = $0 { return true } else { return false } } ? true : nil }
        }
        XCTAssertNil(recorder.snapshot { $0.welcome })
        XCTAssertFalse(recorder.snapshot { $0.states.contains(.connected) })
    }

    func testNewlyPairedDeviceIsAcceptedWithoutRestart() async throws {
        let store = PairingStore(directory: temporaryDirectory())
        _ = try store.pair(name: "first")
        let server = makeServer(store: store, poster: RecordingPoster())
        let port = try await server.start()
        defer { server.stop() }
        let late = try store.pair(name: "late iPad")
        try await Task.sleep(for: .milliseconds(2600))
        let recorder = ClientRecorder()
        let client = ViewportConnection(
            host: "127.0.0.1", port: port, deviceID: late.id, key: late.key,
            hello: Hello(clientName: "late", viewport: PixelSize(width: 640, height: 480)), handlers: recorder.handlers)
        client.start()
        defer { client.cancel() }
        _ = try await eventually("welcome for late device") { recorder.snapshot { $0.welcome } }
    }
}
