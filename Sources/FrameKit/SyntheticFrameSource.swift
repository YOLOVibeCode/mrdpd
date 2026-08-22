/// Deterministic `FrameSource` stub (T1-GFX-01). Yields a packed 2×2 BGRA frame by default.
public struct SyntheticFrameSource: FrameSource, Sendable {
    private let frame: Frame

    public init(frame: Frame = Self.bgra2x2) {
        self.frame = frame
    }

    public func nextFrame() async -> Frame {
        frame
    }

    /// Packed 2×2 BGRA fixture: red, green / blue, white; stride 8; dirty rect = full frame.
    public static let bgra2x2 = Frame(
        width: 2,
        height: 2,
        stride: 8,
        pixels: [
            0x00, 0x00, 0xFF, 0xFF,
            0x00, 0xFF, 0x00, 0xFF,
            0xFF, 0x00, 0x00, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF,
        ]
    )

    /// 1920×1080 packed BGRA: the 2×2 fixture scaled to quadrants (T1-GFX-01 M2).
    public static let pattern1080p = makeQuadrantPattern(width: 1920, height: 1080)
}

private func makeQuadrantPattern(width: UInt32, height: UInt32) -> Frame {
    let stride = width * 4
    var pixels = [UInt8](repeating: 0, count: Int(stride * height))
    let midX = Int(width / 2)
    let midY = Int(height / 2)
    let packedWidth = Int(width)
    for y in 0..<Int(height) {
        let row = y * Int(stride)
        let left: (UInt8, UInt8, UInt8, UInt8) = y < midY ? (0x00, 0x00, 0xFF, 0xFF) : (0xFF, 0x00, 0x00, 0xFF)
        let right: (UInt8, UInt8, UInt8, UInt8) = y < midY ? (0x00, 0xFF, 0x00, 0xFF) : (0xFF, 0xFF, 0xFF, 0xFF)
        for x in 0..<midX {
            let i = row + x * 4
            pixels[i] = left.0
            pixels[i + 1] = left.1
            pixels[i + 2] = left.2
            pixels[i + 3] = left.3
        }
        for x in midX..<packedWidth {
            let i = row + x * 4
            pixels[i] = right.0
            pixels[i + 1] = right.1
            pixels[i + 2] = right.2
            pixels[i + 3] = right.3
        }
    }
    return Frame(width: width, height: height, stride: stride, pixels: pixels)
}
