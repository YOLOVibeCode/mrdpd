import XCTest
import FrameKit

/// T1-GFX-01: `SyntheticFrameSource` is the M0 FrameSource stub.
final class SyntheticFrameSourceTests: XCTestCase {
    func testDefaultSyntheticIs2x2BGRAWithPackedStrideAndFullDirtyRect() async {
        let source = SyntheticFrameSource()
        let frame = await source.nextFrame()

        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 2)
        XCTAssertEqual(frame.stride, 8)
        XCTAssertEqual(frame.pixels.count, 16)
        XCTAssertEqual(frame.dirtyRects, [Rect(x: 0, y: 0, width: 2, height: 2)])
        XCTAssertEqual(frame, SyntheticFrameSource.bgra2x2)
    }

    func testSyntheticPassesFrameSourceContract() async {
        await testFrameSourceContract(SyntheticFrameSource())
    }

    func testInjectedFrameIsYieldedAndStillPassesContract() async {
        let custom = Frame(
            width: 1,
            height: 1,
            stride: 4,
            pixels: [10, 20, 30, 40],
            dirtyRects: [Rect(x: 0, y: 0, width: 1, height: 1)]
        )
        let source = SyntheticFrameSource(frame: custom)

        let frame = await source.nextFrame()
        XCTAssertEqual(frame, custom)
        await testFrameSourceContract(source)
    }
}
