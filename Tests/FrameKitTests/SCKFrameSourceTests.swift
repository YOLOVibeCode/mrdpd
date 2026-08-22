import XCTest
import FrameKit

/// T1-GFX-01: `SCKFrameSource` is the real `FrameSource`. CI skips (R8). `just test-local` requires TCC.
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
