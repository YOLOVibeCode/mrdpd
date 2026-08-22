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

    /// T1-GFX-01 M2: 1920×1080 labeled quadrants (scaled 2×2 fixture), not a 64×64 solid.
    func test1080pPatternIs1920x1080PackedBGRAWithQuadrantColors() async {
        let source = SyntheticFrameSource(frame: SyntheticFrameSource.pattern1080p)
        let frame = await source.nextFrame()

        XCTAssertEqual(frame.width, 1920, "T1-GFX-01: 1080p width")
        XCTAssertEqual(frame.height, 1080, "T1-GFX-01: 1080p height")
        XCTAssertEqual(frame.stride, 1920 * 4, "T1-GFX-01: packed BGRA stride")
        XCTAssertEqual(frame.pixels.count, Int(1920 * 1080 * 4))
        XCTAssertEqual(frame.dirtyRects, [Rect(x: 0, y: 0, width: 1920, height: 1080)])
        XCTAssertEqual(frame, SyntheticFrameSource.pattern1080p)
        guard frame.width == 1920, frame.height == 1080, frame.stride == 1920 * 4 else {
            return
        }

        // Quadrant centers match bgra2x2: red, green / blue, white (BGRA).
        assertPixel(frame, x: 480, y: 270, bgra: [0x00, 0x00, 0xFF, 0xFF], name: "top-left red")
        assertPixel(frame, x: 1440, y: 270, bgra: [0x00, 0xFF, 0x00, 0xFF], name: "top-right green")
        assertPixel(frame, x: 480, y: 810, bgra: [0xFF, 0x00, 0x00, 0xFF], name: "bottom-left blue")
        assertPixel(frame, x: 1440, y: 810, bgra: [0xFF, 0xFF, 0xFF, 0xFF], name: "bottom-right white")

        await testFrameSourceContract(source)
    }
}

private func assertPixel(_ frame: Frame, x: UInt32, y: UInt32, bgra: [UInt8], name: String) {
    let i = Int(y * frame.stride + x * 4)
    XCTAssertEqual(Array(frame.pixels[i..<(i + 4)]), bgra, "T1-GFX-01: \(name)")
}
