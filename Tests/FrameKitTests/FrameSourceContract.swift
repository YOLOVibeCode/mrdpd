import XCTest
import FrameKit

/// Contract suite for any `FrameSource` (T1-GFX-01, B3).
///
/// Invariants every conformer must satisfy — including later `SCKFrameSource`.
/// Size-specific fixtures (2×2) belong on the synthetic stub, not here.
func testFrameSourceContract(_ source: any FrameSource) async {
    let frame = await source.nextFrame()

    XCTAssertGreaterThan(frame.width, 0, "T1-GFX-01: width")
    XCTAssertGreaterThan(frame.height, 0, "T1-GFX-01: height")
    XCTAssertGreaterThanOrEqual(
        frame.stride,
        frame.width * 4,
        "T1-GFX-01: stride >= width * 4 (BGRA)"
    )
    XCTAssertEqual(
        frame.pixels.count,
        Int(frame.stride) * Int(frame.height),
        "T1-GFX-01: pixel buffer is stride * height"
    )

    for rect in frame.dirtyRects {
        XCTAssertGreaterThan(rect.width, 0, "T1-GFX-01: dirty rect width")
        XCTAssertGreaterThan(rect.height, 0, "T1-GFX-01: dirty rect height")
    }
}
