import CoreGraphics
import XCTest
import FrameKit

/// T1-GFX-01: `SCKFrameSource` is the real `FrameSource`. CI skips (R8). `just test-local` requires TCC.
/// T1-MON-02: it captures the main display by default, or the display with the chosen letter.
final class SCKFrameSourceTests: XCTestCase {
    func testSCKFrameSourcePassesFrameSourceContract() async throws {
        try Self.requireLocalCapture()
        let source = try await SCKFrameSource()
        await testFrameSourceContract(source)
        let frame = await source.nextFrame()
        XCTAssertGreaterThan(frame.width, 0, "T1-GFX-01: captured width")
        XCTAssertGreaterThan(frame.height, 0, "T1-GFX-01: captured height")
        XCTAssertFalse(frame.dirtyRects.isEmpty, "T1-GFX-01: dirty list after normalize")
        XCTAssertTrue(source.showsCursor, "T1-GFX-05: cursor composited")
        XCTAssertEqual(source.pixelWidth, frame.width, "T1-IN-03: capture pixels match map")
        XCTAssertEqual(source.pixelHeight, frame.height)
    }

    func testCapturesMainDisplayByDefault() async throws {
        try Self.requireLocalCapture()
        let source = try await SCKFrameSource()
        XCTAssertTrue(source.served.isMain, "T1-MON-02: default is the main display")
        XCTAssertEqual(source.served.displayID, CGMainDisplayID(), "T1-MON-02: CGMainDisplayID")
        XCTAssertEqual(source.pointFrame, source.served.frame, "T1-MON-02: DisplayMap uses the served frame")
    }

    func testCapturesChosenLetter() async throws {
        try Self.requireLocalCapture()
        let catalog = try await SCKFrameSource().catalog
        guard let other = catalog.entries.first(where: { !$0.isMain }) else {
            throw XCTSkip("T1-MON-02: one display; nothing else to choose")
        }
        let source = try await SCKFrameSource(settings: SCKSettings(display: .letter(other.letter)))
        XCTAssertEqual(source.served.displayID, other.displayID, "T1-MON-02: chosen letter")
        XCTAssertEqual(source.pointFrame, other.frame, "T1-MON-02: DisplayMap uses the chosen frame")
        let frame = await source.nextFrame()
        XCTAssertEqual(frame.width, source.pixelWidth, "T1-MON-02: frames come from the chosen display")
    }

    func testUnknownLetterListsAvailable() async throws {
        try Self.requireLocalCapture()
        do {
            _ = try await SCKFrameSource(settings: SCKSettings(display: .letter("ZZ")))
            XCTFail("T1-MON-02: unknown letter must throw")
        } catch let SCKFrameSourceError.unknownDisplay(letter, available) {
            XCTAssertEqual(letter, "ZZ", "T1-MON-02")
            XCTAssertEqual(available.first, "A", "T1-MON-02: available letters")
        }
    }

    private static func requireLocalCapture() throws {
        let env = ProcessInfo.processInfo.environment["MRDPD_TEST_LOCAL"]
        if env != "1" {
            throw XCTSkip("T1-GFX-01: Screen Recording TCC; just test-local")
        }
        if !SCKFrameSource.screenCaptureAllowed {
            XCTFail("T1-OPS-03: Screen Recording TCC missing; see docs/tcc.md")
        }
    }
}
