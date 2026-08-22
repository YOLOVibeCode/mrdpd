import CoreGraphics
import Foundation
import InputKit
import XCTest

/// T1-IN-04: real `InputSink`. CI skips. `just test-local` requires Accessibility.
final class CGEventInputSinkTests: XCTestCase {
    func testDeniedWithoutAccessibilityWhenForced() throws {
        let env = ProcessInfo.processInfo.environment["MRDPD_TEST_LOCAL"]
        if env == "1" {
            throw XCTSkip("T1-IN-04: grant present; denied path is the CI skip / missing-TCC fail")
        }
        if CGEventInputSink.postEventAllowed {
            throw XCTSkip("T1-IN-04: this process already has Accessibility")
        }
        let map = DisplayMap(
            originX: 0,
            originY: 0,
            pointWidth: 10,
            pointHeight: 10,
            pixelWidth: 10,
            pixelHeight: 10
        )
        XCTAssertThrowsError(try CGEventInputSink(map: map)) { error in
            guard case CGEventInputSinkError.denied = error else {
                return XCTFail("T1-IN-04: \(error)")
            }
        }
    }

    func testMouseMovePostsWhenAccessibilityGranted() throws {
        try Self.requireLocalInjection()
        let id = CGMainDisplayID()
        let bounds = CGDisplayBounds(id)
        let map = DisplayMap(
            pointFrame: bounds,
            pixelWidth: UInt32(CGDisplayPixelsWide(id)),
            pixelHeight: UInt32(CGDisplayPixelsHigh(id))
        )
        let sink = try CGEventInputSink(map: map)
        let saved = CGEvent(source: nil)?.location ?? .zero
        defer {
            if let restore = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: saved,
                mouseButton: .left
            ) {
                restore.post(tap: .cghidEventTap)
            }
        }
        let rdpX = Int32(map.pixelWidth / 2)
        let rdpY = Int32(map.pixelHeight / 2)
        let expected = map.cgLocation(rdpX: rdpX, rdpY: rdpY)
        sink.handle(.mouse(x: rdpX, y: rdpY, buttons: 0, wheel: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let got = CGEvent(source: nil)?.location ?? .zero
        XCTAssertEqual(got.x, expected.x, accuracy: 8, "T1-IN-04: mouse x")
        XCTAssertEqual(got.y, expected.y, accuracy: 8, "T1-IN-04: mouse y")
    }

    /// T1-PERF-02: input-to-photon is a live-session measurement, not CI.
    func testPerf02InputToPhotonIsManualInterop() throws {
        throw XCTSkip("T1-PERF-02: input-to-photon < 80 ms on LAN; see docs/bench.md")
    }

    private static func requireLocalInjection() throws {
        let env = ProcessInfo.processInfo.environment["MRDPD_TEST_LOCAL"]
        if env != "1" {
            throw XCTSkip("T1-IN-04: Accessibility TCC; just test-local")
        }
        if !CGEventInputSink.postEventAllowed {
            XCTFail("T1-OPS-03: Accessibility TCC missing; see docs/tcc.md")
        }
    }
}
