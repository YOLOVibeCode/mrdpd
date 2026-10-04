import Foundation

/// One encoded H.264 access unit for a viewport (T1-GFX-07 over the native wire).
///
/// Layout (big-endian): u8 version=1, u8 flags (bit0 keyframe), u32 epoch, u64 captureTimeNanos,
/// u32 width, u32 height, u8 parameterSetCount, then each parameter set as a u32-length blob,
/// then the AVCC payload (4-byte length-prefixed NAL units) to the end of the frame.
public struct VideoPacket: Equatable, Sendable {
    public var epoch: UInt32
    public var isKeyframe: Bool
    /// Host monotonic time of capture; lets the client measure capture → present latency.
    public var captureTimeNanos: UInt64
    public var width: UInt32
    public var height: UInt32
    /// SPS then PPS on keyframes; empty otherwise.
    public var parameterSets: [Data]
    public var avcc: Data

    public init(
        epoch: UInt32, isKeyframe: Bool, captureTimeNanos: UInt64, width: UInt32, height: UInt32,
        parameterSets: [Data], avcc: Data
    ) {
        self.epoch = epoch
        self.isKeyframe = isKeyframe
        self.captureTimeNanos = captureTimeNanos
        self.width = width
        self.height = height
        self.parameterSets = parameterSets
        self.avcc = avcc
    }

    public func frame() -> WireFrame {
        var w = ByteWriter(capacity: 32 + avcc.count + parameterSets.reduce(0) { $0 + $1.count + 4 })
        w.u8(1)
        w.u8(isKeyframe ? 1 : 0)
        w.u32(epoch)
        w.u64(captureTimeNanos)
        w.u32(width)
        w.u32(height)
        w.u8(UInt8(parameterSets.count))
        for set in parameterSets { w.blob(set) }
        w.bytes(avcc)
        return WireFrame(kind: .video, payload: w.data)
    }

    public init(frame: WireFrame) throws {
        guard frame.kind == .video else { throw WireError.malformed("not a video frame") }
        var r = ByteReader(frame.payload)
        guard try r.u8() == 1 else { throw WireError.malformed("video packet version") }
        isKeyframe = try r.u8() & 1 == 1
        epoch = try r.u32()
        captureTimeNanos = try r.u64()
        width = try r.u32()
        height = try r.u32()
        let count = Int(try r.u8())
        var sets: [Data] = []
        for _ in 0..<count { sets.append(try r.blob()) }
        parameterSets = sets
        avcc = r.rest()
    }
}

/// The Mac's cursor, so the client can draw it locally with no video latency (T1-GFX-06).
public struct CursorShape: Equatable, Sendable {
    /// Changes whenever the image changes; lets clients cache.
    public var serial: UInt32
    /// Hotspot and size in points (the client scales to its own pixels).
    public var hotspotX: Double
    public var hotspotY: Double
    public var width: Double
    public var height: Double
    public var png: Data

    public init(serial: UInt32, hotspotX: Double, hotspotY: Double, width: Double, height: Double, png: Data) {
        self.serial = serial
        self.hotspotX = hotspotX
        self.hotspotY = hotspotY
        self.width = width
        self.height = height
        self.png = png
    }
}

/// Layout: u8 kind (0 shape, 1 hidden, 2 visible); shape: u32 serial, f64 hotX, f64 hotY, f64 w, f64 h, PNG.
public enum CursorPacket: Equatable, Sendable {
    case shape(CursorShape)
    /// The Mac cursor is on a different display than this viewport shows.
    case hidden
    case visible

    public func frame() -> WireFrame {
        var w = ByteWriter()
        switch self {
        case .shape(let s):
            w.u8(0)
            w.u32(s.serial)
            w.f64(s.hotspotX)
            w.f64(s.hotspotY)
            w.f64(s.width)
            w.f64(s.height)
            w.bytes(s.png)
        case .hidden:
            w.u8(1)
        case .visible:
            w.u8(2)
        }
        return WireFrame(kind: .cursor, payload: w.data)
    }

    public init(frame: WireFrame) throws {
        guard frame.kind == .cursor else { throw WireError.malformed("not a cursor frame") }
        var r = ByteReader(frame.payload)
        switch try r.u8() {
        case 0:
            self = .shape(
                CursorShape(
                    serial: try r.u32(), hotspotX: try r.f64(), hotspotY: try r.f64(), width: try r.f64(),
                    height: try r.f64(), png: r.rest()))
        case 1: self = .hidden
        case 2: self = .visible
        case let other: throw WireError.malformed("cursor kind \(other)")
        }
    }
}

/// A small JPEG of one display for the picker (T2-NAT-04). Layout: u32 displayID, JPEG bytes.
public struct ThumbnailPacket: Equatable, Sendable {
    public var displayID: UInt32
    public var jpeg: Data

    public init(displayID: UInt32, jpeg: Data) {
        self.displayID = displayID
        self.jpeg = jpeg
    }

    public func frame() -> WireFrame {
        var w = ByteWriter(capacity: 4 + jpeg.count)
        w.u32(displayID)
        w.bytes(jpeg)
        return WireFrame(kind: .thumbnail, payload: w.data)
    }

    public init(frame: WireFrame) throws {
        guard frame.kind == .thumbnail else { throw WireError.malformed("not a thumbnail frame") }
        var r = ByteReader(frame.payload)
        displayID = try r.u32()
        jpeg = r.rest()
    }
}
