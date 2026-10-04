// Encode budget bench (spike R15, ADR 0007). Can this Mac hardware-encode several viewports at
// 60 fps with low per-frame latency at the same time? Paced at 60 fps like a live stream; latency
// is submit → encoded output per frame. Content is desktop-like: a static wallpaper, a document
// window whose glyph grid scrolls 12 px per frame, and a moving block.
//
//   just bench-encode            # H.264 + HEVC, default and speed-priority settings
//
// Not part of `just test`. No TCC needed (synthetic frames, no capture).
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

setvbuf(stdout, nil, _IOLBF, 0)

struct Target: Hashable {
    let name: String
    let w: Int
    let h: Int
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

func makeFrames(_ t: Target, count: Int) -> [CVPixelBuffer] {
    let attrs: [CFString: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey: t.w,
        kCVPixelBufferHeightKey: t.h,
    ]
    var out: [CVPixelBuffer] = []
    for f in 0..<count {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, t.w, t.h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard let pb else { fatalError("pixel buffer") }
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let winX0 = t.w / 6, winX1 = t.w * 5 / 6, winY0 = t.h / 8, winY1 = t.h * 7 / 8
        let scroll = f * 12
        let blockX = (f * 37) % max(t.w - 64, 1)
        for y in 0..<t.h {
            let row = base + y * stride
            for x in 0..<t.w {
                let p = row + x * 4
                if x >= winX0 && x < winX1 && y >= winY0 && y < winY1 {
                    let dy = y - winY0 + scroll
                    let cellX = (x - winX0) / 9, cellY = dy / 18
                    let gx = (x - winX0) % 9, gy = dy % 18
                    var h = UInt32(truncatingIfNeeded: cellX &* 73_856_093)
                        ^ UInt32(truncatingIfNeeded: cellY &* 19_349_663)
                    h = h &* 2_654_435_761
                    let lineEmpty = (cellY % 4 == 3) || (h >> 28) == 0
                    let bit = (h >> UInt32((gx + gy * 3) % 27)) & 1
                    let ink = !lineEmpty && gx < 7 && gy > 3 && gy < 15 && bit == 1
                    let v: UInt8 = ink ? 20 : 250
                    p[0] = v; p[1] = v; p[2] = v; p[3] = 255
                } else if x >= blockX && x < blockX + 64 && y >= t.h - 96 && y < t.h - 32 {
                    p[0] = 30; p[1] = 120; p[2] = 230; p[3] = 255
                } else {
                    p[0] = UInt8(truncatingIfNeeded: 60 + x * 80 / t.w)
                    p[1] = UInt8(truncatingIfNeeded: 40 + y * 60 / t.h)
                    p[2] = 90; p[3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        out.append(pb)
    }
    return out
}

final class Encoder: @unchecked Sendable {
    let target: Target
    let session: VTCompressionSession
    private let lock = NSLock()
    private var lat: [Double] = []
    private var bytes = 0
    private var dropped = 0

    init(_ t: Target, codec: CMVideoCodecType, speed: Bool) {
        target = t
        let spec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true,
        ]
        var s: VTCompressionSession?
        let st = VTCompressionSessionCreate(
            allocator: nil, width: Int32(t.w), height: Int32(t.h), codecType: codec,
            encoderSpecification: spec as CFDictionary, imageBufferAttributes: nil,
            compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard st == noErr, let s else { fatalError("VTCompressionSessionCreate \(st) for \(t.name)") }
        session = s
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 60 as CFNumber)
        // ~41 Mbit/s at 4K, ~28 at iPad 13": LAN-class desktop bitrate.
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: (t.w * t.h * 5) as CFNumber)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 600 as CFNumber)
        VTSessionSetProperty(
            s, key: kVTCompressionPropertyKey_ProfileLevel,
            value: codec == kCMVideoCodecType_H264
                ? kVTProfileLevel_H264_High_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel)
        if speed {
            VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber)
            VTSessionSetProperty(
                s, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        }
        VTCompressionSessionPrepareToEncodeFrames(s)
    }

    func encode(_ pb: CVPixelBuffer, index: Int64) {
        let t0 = now()
        let st = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pb, presentationTimeStamp: CMTime(value: index, timescale: 60),
            duration: .invalid, frameProperties: nil, infoFlagsOut: nil
        ) { [self] status, flags, sbuf in
            let t1 = now()
            lock.lock(); defer { lock.unlock() }
            guard status == noErr, !flags.contains(.frameDropped), let sbuf else { dropped += 1; return }
            lat.append(t1 - t0)
            bytes += CMSampleBufferGetTotalSampleSize(sbuf)
        }
        if st != noErr { lock.lock(); dropped += 1; lock.unlock() }
    }

    func finish() { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) }

    func report(seconds: Double) -> String {
        lock.lock(); defer { lock.unlock() }
        let s = lat.sorted()
        guard !s.isEmpty else { return "\(target.name): no frames (dropped \(dropped))" }
        let q = { (p: Double) in s[min(s.count - 1, Int(Double(s.count) * p))] }
        return String(
            format: "%-22@ %4dx%-4d median %5.1f ms  p95 %5.1f ms  max %5.1f ms  dropped %d  %5.1f Mbit/s",
            target.name as NSString, target.w, target.h, q(0.5), q(0.95), s.last!, dropped,
            Double(bytes) * 8 / 1e6 / seconds)
    }
}

let fourK = Target(name: "4K monitor", w: 3840, h: 2160)
let halfL = Target(name: "4K left half", w: 1920, h: 2160)
let halfR = Target(name: "4K right half", w: 1920, h: 2160)
let iPad = Target(name: "iPad Pro 13", w: 2752, h: 2064)
let qhd = Target(name: "1440p (upscaled)", w: 2560, h: 1440)
let builtIn = Target(name: "MBP 16 built-in", w: 3456, h: 2234)

print("building synthetic frames…")
var frames: [Target: [CVPixelBuffer]] = [:]
for t in [fourK, halfL, halfR, iPad, qhd, builtIn] { frames[t] = makeFrames(t, count: 60) }

func run(_ label: String, codec: CMVideoCodecType, speed: Bool, targets: [Target], fps: [Target: Int] = [:], seconds: Double = 4) {
    let warm = targets.map { Encoder($0, codec: codec, speed: speed) }
    for e in warm { for i in 0..<10 { e.encode(frames[e.target]![i], index: Int64(i)) } }
    for e in warm { e.finish() }
    let encs = targets.map { Encoder($0, codec: codec, speed: speed) }
    let start = now()
    let group = DispatchGroup()
    for e in encs {
        let rate = Double(fps[e.target] ?? 60)
        let total = Int(seconds * rate)
        group.enter()
        Thread.detachNewThread {
            for i in 0..<total {
                let wait = start + Double(i) * 1000.0 / rate - now()
                if wait > 0 { usleep(useconds_t(wait * 1000)) }
                e.encode(frames[e.target]![i % 60], index: Int64(i))
            }
            e.finish()
            group.leave()
        }
    }
    group.wait()
    print("== \(label)")
    for e in encs { print("   " + e.report(seconds: seconds)) }
}

for speed in [false, true] {
    let tag = speed ? " [speed priority]" : ""
    for (codec, cname) in [(kCMVideoCodecType_H264, "H.264"), (kCMVideoCodecType_HEVC, "HEVC")] {
        run("\(cname) 4K alone\(tag)", codec: codec, speed: speed, targets: [fourK])
        run("\(cname) iPad alone\(tag)", codec: codec, speed: speed, targets: [iPad])
        run("\(cname) 4K + iPad\(tag)", codec: codec, speed: speed, targets: [fourK, iPad])
        run("\(cname) 4K as two halves\(tag)", codec: codec, speed: speed, targets: [halfL, halfR])
        run("\(cname) 4K halves + iPad\(tag)", codec: codec, speed: speed, targets: [halfL, halfR, iPad])
        run("\(cname) 1440p + iPad\(tag)", codec: codec, speed: speed, targets: [qhd, iPad])
        run("\(cname) 4K + iPad + built-in\(tag)", codec: codec, speed: speed, targets: [fourK, iPad, builtIn])
    }
}

// Focus policy candidates: the screen you are not using rarely needs 60 fps.
let h264 = kCMVideoCodecType_H264
run("H.264 4K alone @30 [speed priority]", codec: h264, speed: true, targets: [fourK], fps: [fourK: 30])
run("H.264 4K @30 + iPad @60 [speed priority]", codec: h264, speed: true, targets: [fourK, iPad], fps: [fourK: 30])
run("H.264 4K halves @60 + iPad @30 [speed priority]", codec: h264, speed: true, targets: [halfL, halfR, iPad], fps: [iPad: 30])
run("H.264 4K halves @60 + iPad @15 [speed priority]", codec: h264, speed: true, targets: [halfL, halfR, iPad], fps: [iPad: 15])
