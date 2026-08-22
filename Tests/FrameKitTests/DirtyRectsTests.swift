import XCTest
import FrameKit

/// T1-GFX-01 / T1-GFX-04: dirty list is frame-local. Empty means full frame (ABI v1).
/// Not a `FrameSource` method (ISP).
final class DirtyRectsTests: XCTestCase {
    func testEmptyListMeansFullFrame() {
        let out = DirtyRects.normalized([], frameWidth: 1920, frameHeight: 1080)
        XCTAssertEqual(out, [Rect(x: 0, y: 0, width: 1920, height: 1080)])
    }

    func testClipsToFrameBounds() {
        let out = DirtyRects.normalized(
            [Rect(x: -10, y: -5, width: 30, height: 20)],
            frameWidth: 64,
            frameHeight: 32
        )
        XCTAssertEqual(out, [Rect(x: 0, y: 0, width: 20, height: 15)])
    }

    func testDropsRectsCompletelyOutside() {
        let out = DirtyRects.normalized(
            [Rect(x: 100, y: 100, width: 10, height: 10)],
            frameWidth: 64,
            frameHeight: 32
        )
        XCTAssertEqual(out, [Rect(x: 0, y: 0, width: 64, height: 32)], "T1-GFX-01: all-outside → full frame")
    }
}
