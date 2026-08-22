import CoreVideo

/// BGRA `Frame` from a `CVPixelBuffer` (T1-GFX-01). TCC-free helper used by `SCKFrameSource`.
public enum CaptureFrame {
    public static func make(pixelBuffer: CVPixelBuffer, dirty: [Rect]) -> Frame? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else {
            return nil
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0, width <= Int(UInt32.max), height <= Int(UInt32.max) else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard stride >= width * 4 else {
            return nil
        }
        let nbytes = stride * height
        let pixels = Array(UnsafeRawBufferPointer(start: base, count: nbytes))
        let w = UInt32(width)
        let h = UInt32(height)
        return Frame(
            width: w,
            height: h,
            stride: UInt32(stride),
            pixels: pixels,
            dirtyRects: DirtyRects.normalized(dirty, frameWidth: w, frameHeight: h)
        )
    }
}
