import Foundation

/// T1-VP-02: picture geometry shared by host and client. Pure functions, no platform types.
public enum ViewportGeometry {
    /// One hardware encoder keeps up with about this many pixels per frame at 60 fps on an
    /// M4 Max (spike R15: 2752×2064 at ~15 ms). Above it, 60 fps latency balloons.
    public static let maxPixelsAt60fps = 2752 * 2064

    /// The largest rect with `contentAspect` that fits `container`, centered (aspect fit).
    public static func aspectFit(contentAspect: Double, in container: RectD) -> RectD {
        guard contentAspect > 0, container.width > 0, container.height > 0 else { return container }
        let containerAspect = container.width / container.height
        if contentAspect > containerAspect {
            let h = container.width / contentAspect
            return RectD(x: container.x, y: container.y + (container.height - h) / 2, width: container.width, height: h)
        }
        let w = container.height * contentAspect
        return RectD(x: container.x + (container.width - w) / 2, y: container.y, width: w, height: container.height)
    }

    /// Encoded picture size for a viewport showing `source`: the source's aspect fitted into the
    /// viewport, never larger than the source's own pixels, at most `maxPixels`, even dimensions
    /// (H.264 4:2:0), at least 64 px on each side.
    public static func encodeSize(source: PixelSize, viewport: PixelSize, maxPixels: Int = maxPixelsAt60fps) -> PixelSize {
        guard source.width > 0, source.height > 0, viewport.width > 0, viewport.height > 0 else {
            return PixelSize(width: 64, height: 64)
        }
        let aspect = Double(source.width) / Double(source.height)
        let fit = aspectFit(contentAspect: aspect, in: RectD(x: 0, y: 0, width: Double(viewport.width), height: Double(viewport.height)))
        var w = min(fit.width, Double(source.width))
        var h = min(fit.height, Double(source.height))
        // Keep the aspect when the source clamp bit only one axis.
        if w / h > aspect { w = h * aspect } else { h = w / aspect }
        if w * h > Double(maxPixels) {
            let scale = (Double(maxPixels) / (w * h)).squareRoot()
            w *= scale
            h *= scale
        }
        func even(_ v: Double) -> Int { max(64, Int(v / 2) * 2) }
        return PixelSize(width: even(w), height: even(h))
    }

    /// Normalized picture point → Quartz global point on the source display.
    public static func globalPoint(_ p: Point01, displayFrame: RectD) -> (x: Double, y: Double) {
        let c = p.clamped()
        // Stay inside the display: x == width would land on the next display to the right.
        let x = displayFrame.x + min(c.x * displayFrame.width, displayFrame.width - 0.5)
        let y = displayFrame.y + min(c.y * displayFrame.height, displayFrame.height - 0.5)
        return (x, y)
    }

    /// A point in the client's view → normalized picture point, given where the picture is drawn.
    public static func normalized(viewX: Double, viewY: Double, pictureRect: RectD) -> Point01 {
        guard pictureRect.width > 0, pictureRect.height > 0 else { return Point01(x: 0, y: 0) }
        return Point01(x: (viewX - pictureRect.x) / pictureRect.width, y: (viewY - pictureRect.y) / pictureRect.height)
            .clamped()
    }

    /// 1-based arrangement order for displays: left→right when the arrangement is wider than
    /// tall, top→bottom otherwise (the owner's Mac stacks its displays vertically).
    public static func arrangementOrder(_ frames: [UInt32: RectD]) -> [UInt32] {
        guard !frames.isEmpty else { return [] }
        let minX = frames.values.map(\.x).min()!
        let maxX = frames.values.map { $0.x + $0.width }.max()!
        let minY = frames.values.map(\.y).min()!
        let maxY = frames.values.map { $0.y + $0.height }.max()!
        let horizontal = (maxX - minX) >= (maxY - minY)
        return frames.sorted { a, b in
            let (pa, sa) = horizontal ? (a.value.midX, a.value.midY) : (a.value.midY, a.value.midX)
            let (pb, sb) = horizontal ? (b.value.midX, b.value.midY) : (b.value.midY, b.value.midX)
            if pa != pb { return pa < pb }
            if sa != sb { return sa < sb }
            return a.key < b.key
        }.map(\.key)
    }
}
