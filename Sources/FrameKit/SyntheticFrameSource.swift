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
}
