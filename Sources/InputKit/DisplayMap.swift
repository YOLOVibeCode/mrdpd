import CoreGraphics

/// RDP virtual-desktop pixels → Quartz global coordinates (T1-IN-03).
/// Origin is the upper-left of the captured display in global display space (Y down).
/// Not part of `InputSink` (ISP).
public struct DisplayMap: Sendable, Equatable {
    public var originX: Double
    public var originY: Double
    public var pointWidth: Double
    public var pointHeight: Double
    public var pixelWidth: Double
    public var pixelHeight: Double

    public init(
        originX: Double,
        originY: Double,
        pointWidth: Double,
        pointHeight: Double,
        pixelWidth: Double,
        pixelHeight: Double
    ) {
        self.originX = originX
        self.originY = originY
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public init(pointFrame: CGRect, pixelWidth: UInt32, pixelHeight: UInt32) {
        self.init(
            originX: pointFrame.origin.x,
            originY: pointFrame.origin.y,
            pointWidth: pointFrame.width,
            pointHeight: pointFrame.height,
            pixelWidth: Double(pixelWidth),
            pixelHeight: Double(pixelHeight)
        )
    }

    /// Quartz global point for an RDP mouse coordinate (virtual-desktop pixels).
    public func cgLocation(rdpX: Int32, rdpY: Int32) -> CGPoint {
        let maxPx = max(pixelWidth - 1, 0)
        let maxPy = max(pixelHeight - 1, 0)
        let px = min(max(Double(rdpX), 0), maxPx)
        let py = min(max(Double(rdpY), 0), maxPy)
        let sx = pixelWidth > 0 ? pointWidth / pixelWidth : 1
        let sy = pixelHeight > 0 ? pointHeight / pixelHeight : 1
        return CGPoint(x: originX + px * sx, y: originY + py * sy)
    }
}
