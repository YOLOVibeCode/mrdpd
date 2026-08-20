/// Pixel-space rectangle. Matches C ABI `MrdpdRect` field roles (`x`/`y` signed, `width`/`height` unsigned).
public struct Rect: Sendable, Equatable {
    public var x: Int32
    public var y: Int32
    public var width: UInt32
    public var height: UInt32

    public init(x: Int32, y: Int32, width: UInt32, height: UInt32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Packed or padded BGRA8888 bitmap.
public struct Frame: Sendable, Equatable {
    public let width: UInt32
    public let height: UInt32
    /// Bytes per row; must be >= `width * 4`.
    public let stride: UInt32
    public let pixels: [UInt8]
    public let dirtyRects: [Rect]

    public init(
        width: UInt32,
        height: UInt32,
        stride: UInt32,
        pixels: [UInt8],
        dirtyRects: [Rect]? = nil
    ) {
        self.width = width
        self.height = height
        self.stride = stride
        self.pixels = pixels
        self.dirtyRects = dirtyRects ?? [Rect(x: 0, y: 0, width: width, height: height)]
    }
}
