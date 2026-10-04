import Foundation
import XCTest

@testable import ViewportProtocol

/// T2-NAT-01: framing and message contracts shared by host and client.
final class WireTests: XCTestCase {
    func testFrameRoundTripsThroughDecoder() throws {
        let frame = WireFrame(kind: .video, payload: Data([1, 2, 3, 4, 5]))
        var decoder = WireDecoder()
        XCTAssertEqual(try decoder.append(frame.encoded()), [frame])
    }

    func testDecoderHandlesOneByteAtATime() throws {
        let frames = [
            WireFrame(kind: .control, payload: Data("{}".utf8)),
            WireFrame(kind: .thumbnail, payload: Data(repeating: 7, count: 300)),
            WireFrame(kind: .cursor, payload: Data([1])),
        ]
        let bytes = frames.map { $0.encoded() }.reduce(Data(), +)
        var decoder = WireDecoder()
        var out: [WireFrame] = []
        for b in bytes { out += try decoder.append(Data([b])) }
        XCTAssertEqual(out, frames)
    }

    func testDecoderReturnsSeveralFramesFromOneChunk() throws {
        let a = WireFrame(kind: .control, payload: Data("a".utf8))
        let b = WireFrame(kind: .control, payload: Data("bb".utf8))
        var decoder = WireDecoder()
        XCTAssertEqual(try decoder.append(a.encoded() + b.encoded()), [a, b])
    }

    func testOversizeFrameIsRejected() {
        var w = ByteWriter()
        w.u32(UInt32(WireDecoder.maxFrameBytes + 1))
        w.u8(WireKind.video.rawValue)
        var decoder = WireDecoder()
        XCTAssertThrowsError(try decoder.append(w.data)) { error in
            XCTAssertEqual(error as? WireError, .frameTooLarge(WireDecoder.maxFrameBytes + 1))
        }
    }

    func testUnknownKindIsRejected() {
        var w = ByteWriter()
        w.u32(1)
        w.u8(99)
        var decoder = WireDecoder()
        XCTAssertThrowsError(try decoder.append(w.data)) { error in
            XCTAssertEqual(error as? WireError, .unknownKind(99))
        }
    }
}

final class ControlTests: XCTestCase {
    func testClientMessagesRoundTrip() throws {
        let messages: [ClientMessage] = [
            .hello(Hello(clientName: "iPad Pro", viewport: PixelSize(width: 2752, height: 2064), preferredDisplayID: 4)),
            .subscribe(displayID: 5),
            .resize(PixelSize(width: 3840, height: 2160)),
            .focus(false),
            .input(.key(usage: HIDUsage.a, down: true)),
            .input(.button(.right, down: true, at: Point01(x: 0.25, y: 0.75), clickCount: 2)),
            .input(.scroll(dx: 0, dy: -12.5, phase: .changed, momentum: .none)),
            .input(.wheel(dx: 0, dy: 3)),
            .input(.move(Point01(x: 0.5, y: 0.5))),
            .input(.releaseAll),
            .requestKeyframe,
            .requestThumbnails(maxWidth: 320),
            .ping(id: 9),
        ]
        for m in messages {
            XCTAssertEqual(try ControlCodec.clientMessage(try ControlCodec.frame(m)), m)
        }
    }

    func testHostMessagesRoundTrip() throws {
        let display = DisplayInfo(
            id: 1, index: 3, name: "Built-in Retina Display", isBuiltin: true, isMain: true,
            frame: RectD(x: 0, y: 0, width: 1728, height: 1117), pixelSize: PixelSize(width: 3456, height: 2234))
        let messages: [HostMessage] = [
            .welcome(Welcome(hostName: "Mac", hostID: "abc", displays: [display])),
            .displays([display]),
            .stream(StreamInfo(displayID: 1, epoch: 2, contentSize: PixelSize(width: 2752, height: 1778), fps: 60)),
            .pong(id: 9),
            .bye(reason: "unpaired"),
        ]
        for m in messages {
            XCTAssertEqual(try ControlCodec.hostMessage(try ControlCodec.frame(m)), m)
        }
    }

    func testControlDecoderRejectsVideoFrames() {
        XCTAssertThrowsError(try ControlCodec.clientMessage(WireFrame(kind: .video, payload: Data())))
    }
}

final class PacketTests: XCTestCase {
    func testVideoPacketRoundTrip() throws {
        let p = VideoPacket(
            epoch: 3, isKeyframe: true, captureTimeNanos: 123_456_789, width: 2752, height: 2064,
            parameterSets: [Data([0x67, 1, 2]), Data([0x68, 3])], avcc: Data([0, 0, 0, 2, 0x65, 0x88]))
        XCTAssertEqual(try VideoPacket(frame: p.frame()), p)
    }

    func testDeltaVideoPacketHasNoParameterSets() throws {
        let p = VideoPacket(
            epoch: 3, isKeyframe: false, captureTimeNanos: 1, width: 64, height: 64, parameterSets: [],
            avcc: Data([0, 0, 0, 1, 0x41]))
        XCTAssertEqual(try VideoPacket(frame: p.frame()), p)
    }

    func testTruncatedVideoPacketThrows() {
        XCTAssertThrowsError(try VideoPacket(frame: WireFrame(kind: .video, payload: Data([1, 1, 0]))))
    }

    func testCursorPacketsRoundTrip() throws {
        for p in [
            CursorPacket.shape(CursorShape(serial: 7, hotspotX: 5, hotspotY: 5, width: 28, height: 40, png: Data([0x89, 0x50]))),
            .hidden, .visible,
        ] {
            XCTAssertEqual(try CursorPacket(frame: p.frame()), p)
        }
    }

    func testThumbnailRoundTrip() throws {
        let t = ThumbnailPacket(displayID: 5, jpeg: Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(try ThumbnailPacket(frame: t.frame()), t)
    }
}

/// T1-VP-02: geometry on the owner's real layout (ADR 0006).
final class GeometryTests: XCTestCase {
    func testAspectFitPillarboxesAndLetterboxes() {
        let fourK = RectD(x: 0, y: 0, width: 3840, height: 2160)
        let pillar = ViewportGeometry.aspectFit(contentAspect: 4.0 / 3.0, in: fourK)
        XCTAssertEqual(pillar, RectD(x: 480, y: 0, width: 2880, height: 2160))
        let letter = ViewportGeometry.aspectFit(contentAspect: 16.0 / 9.0, in: RectD(x: 0, y: 0, width: 2752, height: 2064))
        XCTAssertEqual(letter.width, 2752)
        XCTAssertEqual(letter.y, (2064 - 1548) / 2)
    }

    func testFourByThreeDisplayOnIPadIsExactAndUnderTheCap() {
        let s = ViewportGeometry.encodeSize(
            source: PixelSize(width: 3200, height: 2400), viewport: PixelSize(width: 2752, height: 2064))
        XCTAssertEqual(s, PixelSize(width: 2752, height: 2064))
    }

    func testFourByThreeDisplayOn4KIsCappedForSixtyFps() {
        let s = ViewportGeometry.encodeSize(
            source: PixelSize(width: 3200, height: 2400), viewport: PixelSize(width: 3840, height: 2160))
        XCTAssertLessThanOrEqual(s.pixels, ViewportGeometry.maxPixelsAt60fps)
        XCTAssertEqual(Double(s.width) / Double(s.height), 4.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(s.width % 2, 0)
        XCTAssertEqual(s.height % 2, 0)
    }

    func testNeverUpscalesBeyondTheSource() {
        let s = ViewportGeometry.encodeSize(
            source: PixelSize(width: 1600, height: 1200), viewport: PixelSize(width: 3840, height: 2160))
        XCTAssertEqual(s, PixelSize(width: 1600, height: 1200))
    }

    func testBuiltInOnFourKKeepsAspect() {
        let s = ViewportGeometry.encodeSize(
            source: PixelSize(width: 3456, height: 2234), viewport: PixelSize(width: 3840, height: 2160),
            maxPixels: .max)
        XCTAssertEqual(s.height, 2160)
        XCTAssertEqual(Double(s.width) / Double(s.height), 3456.0 / 2234.0, accuracy: 0.01)
    }

    func testGlobalPointHonorsNegativeOriginsAndStaysOnTheDisplay() {
        let sceptre = RectD(x: -629, y: -2160, width: 1600, height: 1200)
        let mid = ViewportGeometry.globalPoint(Point01(x: 0.5, y: 0.5), displayFrame: sceptre)
        XCTAssertEqual(mid.x, 171)
        XCTAssertEqual(mid.y, -1560)
        let corner = ViewportGeometry.globalPoint(Point01(x: 1, y: 1), displayFrame: sceptre)
        XCTAssertLessThan(corner.x, sceptre.x + sceptre.width)
        XCTAssertLessThan(corner.y, sceptre.y + sceptre.height)
    }

    func testNormalizedClampsIntoThePicture() {
        let picture = RectD(x: 480, y: 0, width: 2880, height: 2160)
        XCTAssertEqual(ViewportGeometry.normalized(viewX: 1920, viewY: 1080, pictureRect: picture), Point01(x: 0.5, y: 0.5))
        XCTAssertEqual(ViewportGeometry.normalized(viewX: 10, viewY: 3000, pictureRect: picture), Point01(x: 0, y: 1))
    }

    func testOwnersStackedLayoutIsOrderedTopToBottom() {
        let frames: [UInt32: RectD] = [
            1: RectD(x: 0, y: 0, width: 1728, height: 1117),
            4: RectD(x: 971, y: -1200, width: 1600, height: 1200),
            5: RectD(x: -629, y: -2160, width: 1600, height: 1200),
        ]
        XCTAssertEqual(ViewportGeometry.arrangementOrder(frames), [5, 4, 1])
    }

    func testSideBySideLayoutIsOrderedLeftToRight() {
        let frames: [UInt32: RectD] = [
            2: RectD(x: 1728, y: 0, width: 1920, height: 1080),
            1: RectD(x: 0, y: 0, width: 1728, height: 1117),
            3: RectD(x: -1920, y: 0, width: 1920, height: 1080),
        ]
        XCTAssertEqual(ViewportGeometry.arrangementOrder(frames), [3, 1, 2])
    }
}

/// T2-NAT-02: pairing link format.
final class PairingTests: XCTestCase {
    let key = Data((0..<32).map { UInt8($0) })

    func testLinkRoundTrips() {
        let link = PairingLink(
            hostName: "Ricardo's MacBook Pro", hostID: "H1", address: "100.109.3.105", port: 3399, deviceID: "D1", key: key)
        XCTAssertEqual(PairingLink(url: link.url), link)
    }

    func testIPv6AddressRoundTrips() {
        let link = PairingLink(hostName: "Mac", hostID: "H1", address: "fd7a:115c:a1e0::1", port: 3399, deviceID: "D1", key: key)
        XCTAssertEqual(PairingLink(url: link.url)?.address, "fd7a:115c:a1e0::1")
    }

    func testRejectsShortKeyWrongSchemeAndMissingPort() {
        let good = PairingLink(hostName: "Mac", hostID: "H1", address: "127.0.0.1", port: 3399, deviceID: "D1", key: key)
        XCTAssertNil(PairingLink(url: good.url.replacingOccurrences(of: "mrdpd://", with: "https://")))
        XCTAssertNil(PairingLink(url: good.url.replacingOccurrences(of: "port=3399", with: "port=0")))
        var short = good
        short.key = Data(repeating: 1, count: 16)
        XCTAssertNil(PairingLink(url: short.url))
    }

    func testToleratesSurroundingWhitespace() {
        let link = PairingLink(hostName: "Mac", hostID: "H1", address: "127.0.0.1", port: 3399, deviceID: "D1", key: key)
        XCTAssertEqual(PairingLink(url: "  \(link.url)\n"), link)
    }
}

/// T1-VP-03: switch shortcuts.
final class ShortcutTests: XCTestCase {
    let displays = [
        DisplayInfo(id: 5, index: 1, name: "Top", isBuiltin: false, isMain: false, frame: RectD(x: 0, y: 0, width: 1, height: 1), pixelSize: PixelSize(width: 1, height: 1)),
        DisplayInfo(id: 4, index: 2, name: "Middle", isBuiltin: false, isMain: false, frame: RectD(x: 0, y: 0, width: 1, height: 1), pixelSize: PixelSize(width: 1, height: 1)),
        DisplayInfo(id: 1, index: 3, name: "Built-in", isBuiltin: true, isMain: true, frame: RectD(x: 0, y: 0, width: 1, height: 1), pixelSize: PixelSize(width: 1, height: 1)),
    ]

    func testControlOptionDigitPicksDisplay() {
        var s = SwitchShortcuts()
        XCTAssertNil(s.handle(usage: HIDUsage.leftControl, down: true))
        XCTAssertNil(s.handle(usage: HIDUsage.leftOption, down: true))
        XCTAssertEqual(s.handle(usage: HIDUsage.digit1 + 1, down: true), .display(index: 2))
        XCTAssertEqual(s.handle(usage: HIDUsage.digit0, down: true), .picker)
        XCTAssertEqual(s.handle(usage: HIDUsage.rightBracket, down: true), .next)
    }

    func testCommandOrMissingOptionIsNotAShortcut() {
        var s = SwitchShortcuts()
        _ = s.handle(usage: HIDUsage.leftControl, down: true)
        XCTAssertNil(s.handle(usage: HIDUsage.digit1, down: true))
        _ = s.handle(usage: HIDUsage.leftOption, down: true)
        _ = s.handle(usage: HIDUsage.leftCommand, down: true)
        XCTAssertNil(s.handle(usage: HIDUsage.digit1, down: true))
    }

    func testReleasedModifiersStopMatching() {
        var s = SwitchShortcuts()
        _ = s.handle(usage: HIDUsage.leftControl, down: true)
        _ = s.handle(usage: HIDUsage.leftOption, down: true)
        _ = s.handle(usage: HIDUsage.leftOption, down: false)
        XCTAssertNil(s.handle(usage: HIDUsage.digit1, down: true))
    }

    func testNextAndPreviousWrapInArrangementOrder() {
        XCTAssertEqual(SwitchShortcuts.target(.next, current: 1, displays: displays), 5)
        XCTAssertEqual(SwitchShortcuts.target(.previous, current: 5, displays: displays), 1)
        XCTAssertEqual(SwitchShortcuts.target(.display(index: 3), current: 5, displays: displays), 1)
        XCTAssertNil(SwitchShortcuts.target(.display(index: 9), current: 5, displays: displays))
    }
}
