/// Frame-local dirty rects (T1-GFX-01 / T1-GFX-04). Pure data. Not a `FrameSource` method (ISP).
///
/// Empty input means full frame, matching ABI v1 `push_frame`.
public enum DirtyRects {
    public static func normalized(_ rects: [Rect], frameWidth: UInt32, frameHeight: UInt32) -> [Rect] {
        if frameWidth == 0 || frameHeight == 0 {
            return []
        }
        var out: [Rect] = []
        out.reserveCapacity(rects.count)
        for rect in rects {
            if let clipped = clip(rect, frameWidth: frameWidth, frameHeight: frameHeight) {
                out.append(clipped)
            }
        }
        if out.isEmpty {
            return [Rect(x: 0, y: 0, width: frameWidth, height: frameHeight)]
        }
        return out
    }

    public static func clip(_ rect: Rect, frameWidth: UInt32, frameHeight: UInt32) -> Rect? {
        let left = max(Int64(rect.x), 0)
        let top = max(Int64(rect.y), 0)
        let right = min(Int64(rect.x) + Int64(rect.width), Int64(frameWidth))
        let bottom = min(Int64(rect.y) + Int64(rect.height), Int64(frameHeight))
        if right <= left || bottom <= top {
            return nil
        }
        return Rect(
            x: Int32(left),
            y: Int32(top),
            width: UInt32(right - left),
            height: UInt32(bottom - top)
        )
    }
}
