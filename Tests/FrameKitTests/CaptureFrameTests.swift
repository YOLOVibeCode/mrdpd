import XCTest
import CoreVideo
import FrameKit

/// T1-GFX-01: packed/padded BGRA copy from a pixel buffer (TCC-free; no SCK).
final class CaptureFrameTests: XCTestCase {
    func testCopies2x2BGRARespectingStride() {
        let buffer = makeBGRABuffer(
            width: 2,
            height: 2,
            pixels: [
                0x00, 0x00, 0xFF, 0xFF,
                0x00, 0xFF, 0x00, 0xFF,
                0xFF, 0x00, 0x00, 0xFF,
                0xFF, 0xFF, 0xFF, 0xFF,
            ]
        )
        let frame = CaptureFrame.make(
            pixelBuffer: buffer,
            dirty: [Rect(x: 0, y: 0, width: 1, height: 1)]
        )
        XCTAssertNotNil(frame, "T1-GFX-01: BGRA copy")
        guard let frame else { return }
        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 2)
        XCTAssertGreaterThanOrEqual(frame.stride, 8)
        XCTAssertEqual(frame.pixels.count, Int(frame.stride) * 2)
        XCTAssertEqual(Array(frame.pixels[0..<4]), [0x00, 0x00, 0xFF, 0xFF])
        let row1 = Int(frame.stride)
        XCTAssertEqual(Array(frame.pixels[row1..<(row1 + 4)]), [0xFF, 0x00, 0x00, 0xFF])
        XCTAssertEqual(frame.dirtyRects, [Rect(x: 0, y: 0, width: 1, height: 1)])
    }

    func testEmptyDirtyBecomesFullFrame() {
        let buffer = makeBGRABuffer(width: 2, height: 1, pixels: [1, 2, 3, 4, 5, 6, 7, 8])
        let frame = CaptureFrame.make(pixelBuffer: buffer, dirty: [])
        XCTAssertEqual(frame?.dirtyRects, [Rect(x: 0, y: 0, width: 2, height: 1)])
    }
}

private func makeBGRABuffer(width: Int, height: Int, pixels: [UInt8]) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
        &buffer
    )
    XCTAssertEqual(status, kCVReturnSuccess)
    let pb = buffer!
    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }
    let stride = CVPixelBufferGetBytesPerRow(pb)
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let src = (y * width + x) * 4
            let dst = y * stride + x * 4
            base[dst] = pixels[src]
            base[dst + 1] = pixels[src + 1]
            base[dst + 2] = pixels[src + 2]
            base[dst + 3] = pixels[src + 3]
        }
    }
    return pb
}
