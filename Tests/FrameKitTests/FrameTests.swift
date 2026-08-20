import XCTest
import FrameKit

/// T1-GFX-01: BGRA frames with stride + dirty rects (value type only; no protocol).
final class FrameTests: XCTestCase {
    func test2x2BGRAHasPackedStrideAndPixelCount() {
        let pixels = packedBGRA2x2Pixels()
        let frame = Frame(width: 2, height: 2, stride: 8, pixels: pixels)

        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 2)
        XCTAssertEqual(frame.stride, 8)
        XCTAssertGreaterThanOrEqual(frame.stride, frame.width * 4)
        XCTAssertEqual(frame.pixels.count, Int(frame.stride) * Int(frame.height))
        XCTAssertEqual(frame.pixels, pixels)
    }

    func test2x2StoresBytesInBGRAChannelOrder() {
        let pixels: [UInt8] = [
            1, 2, 3, 255, 0, 0, 0, 255,
            0, 0, 0, 255, 0, 0, 0, 255,
        ]
        let frame = Frame(width: 2, height: 2, stride: 8, pixels: pixels)

        XCTAssertEqual(frame.pixels[0], 1) // B
        XCTAssertEqual(frame.pixels[1], 2) // G
        XCTAssertEqual(frame.pixels[2], 3) // R
        XCTAssertEqual(frame.pixels[3], 255) // A
    }

    func testStrideMayExceedPackedRowWidth() {
        let stride: UInt32 = 16
        var pixels = [UInt8](repeating: 0, count: Int(stride * 2))
        pixels[0] = 9
        pixels[Int(stride)] = 8

        let frame = Frame(width: 2, height: 2, stride: stride, pixels: pixels)

        XCTAssertEqual(frame.stride, 16)
        XCTAssertGreaterThan(frame.stride, frame.width * 4)
        XCTAssertEqual(frame.pixels.count, 32)
        XCTAssertEqual(frame.pixels[0], 9)
        XCTAssertEqual(frame.pixels[16], 8)
    }

    func testDefaultDirtyRectIsFullFrame() {
        let frame = Frame(width: 2, height: 2, stride: 8, pixels: packedBGRA2x2Pixels())

        XCTAssertEqual(frame.dirtyRects, [Rect(x: 0, y: 0, width: 2, height: 2)])
    }

    func testExplicitDirtyRectsArePreserved() {
        let dirty = [Rect(x: 0, y: 0, width: 1, height: 1)]
        let frame = Frame(
            width: 2,
            height: 2,
            stride: 8,
            pixels: packedBGRA2x2Pixels(),
            dirtyRects: dirty
        )

        XCTAssertEqual(frame.dirtyRects, dirty)
    }
}

private func packedBGRA2x2Pixels() -> [UInt8] {
    [
        0x00, 0x00, 0xFF, 0xFF, // (0,0) red in BGRA
        0x00, 0xFF, 0x00, 0xFF, // (1,0) green
        0xFF, 0x00, 0x00, 0xFF, // (0,1) blue
        0xFF, 0xFF, 0xFF, 0xFF, // (1,1) white
    ]
}
