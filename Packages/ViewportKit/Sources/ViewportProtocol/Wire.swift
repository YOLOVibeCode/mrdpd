import Foundation

/// T2-NAT-01: one frame on the wire is a 4-byte big-endian length (covering kind + payload),
/// a 1-byte kind, then the payload. TLS (ViewportTransport) carries the frames.
public enum WireKind: UInt8, Sendable {
    /// JSON `ClientMessage` / `HostMessage`.
    case control = 1
    /// Binary `VideoPacket`.
    case video = 2
    /// Binary `CursorPacket`.
    case cursor = 3
    /// Binary `ThumbnailPacket`.
    case thumbnail = 4
}

public struct WireFrame: Equatable, Sendable {
    public var kind: WireKind
    public var payload: Data

    public init(kind: WireKind, payload: Data) {
        self.kind = kind
        self.payload = payload
    }

    public func encoded() -> Data {
        var out = ByteWriter(capacity: 5 + payload.count)
        out.u32(UInt32(1 + payload.count))
        out.u8(kind.rawValue)
        out.bytes(payload)
        return out.data
    }
}

public enum WireError: Error, Equatable, Sendable {
    case frameTooLarge(Int)
    case unknownKind(UInt8)
    case truncated
    case malformed(String)
}

/// Incremental frame decoder. Feed it whatever the socket returned; it yields complete frames.
public struct WireDecoder: Sendable {
    /// Upper bound for one frame. A 4K keyframe at LAN bitrates is ~1–3 MB.
    public static let maxFrameBytes = 32 << 20

    private var buffer = Data()

    public init() {}

    public mutating func append(_ bytes: Data) throws -> [WireFrame] {
        buffer.append(bytes)
        var frames: [WireFrame] = []
        var reader = ByteReader(buffer)
        while reader.remaining >= 5 {
            let mark = reader.offset
            let length = Int(try reader.u32())
            guard length >= 1, length <= Self.maxFrameBytes else {
                throw WireError.frameTooLarge(length)
            }
            guard reader.remaining >= length else {
                reader.offset = mark
                break
            }
            let kindByte = try reader.u8()
            guard let kind = WireKind(rawValue: kindByte) else {
                throw WireError.unknownKind(kindByte)
            }
            frames.append(WireFrame(kind: kind, payload: try reader.bytes(length - 1)))
        }
        buffer = Data(buffer.suffix(from: buffer.startIndex + reader.offset))
        return frames
    }
}

/// Big-endian binary writer for the packet formats.
public struct ByteWriter: Sendable {
    public private(set) var data: Data

    public init(capacity: Int = 64) {
        data = Data()
        data.reserveCapacity(capacity)
    }

    public mutating func u8(_ v: UInt8) { data.append(v) }

    public mutating func u16(_ v: UInt16) {
        data.append(UInt8(v >> 8))
        data.append(UInt8(v & 0xFF))
    }

    public mutating func u32(_ v: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) { data.append(UInt8((v >> UInt32(shift)) & 0xFF)) }
    }

    public mutating func u64(_ v: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8((v >> UInt64(shift)) & 0xFF)) }
    }

    public mutating func f64(_ v: Double) { u64(v.bitPattern) }

    public mutating func bytes(_ d: Data) { data.append(d) }

    /// u32 length prefix, then the bytes.
    public mutating func blob(_ d: Data) {
        u32(UInt32(d.count))
        data.append(d)
    }
}

/// Big-endian binary reader. Throws `WireError.truncated` instead of trapping.
public struct ByteReader: Sendable {
    private let data: Data
    public var offset: Int

    public init(_ data: Data) {
        self.data = Data(data)
        offset = 0
    }

    public var remaining: Int { data.count - offset }

    public mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw WireError.truncated }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    public mutating func u16() throws -> UInt16 {
        UInt16(try u8()) << 8 | UInt16(try u8())
    }

    public mutating func u32() throws -> UInt32 {
        var v: UInt32 = 0
        for _ in 0..<4 { v = v << 8 | UInt32(try u8()) }
        return v
    }

    public mutating func u64() throws -> UInt64 {
        var v: UInt64 = 0
        for _ in 0..<8 { v = v << 8 | UInt64(try u8()) }
        return v
    }

    public mutating func f64() throws -> Double { Double(bitPattern: try u64()) }

    public mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, remaining >= count else { throw WireError.truncated }
        defer { offset += count }
        let start = data.startIndex + offset
        return data.subdata(in: start..<start + count)
    }

    public mutating func blob() throws -> Data { try bytes(Int(try u32())) }

    public mutating func rest() -> Data {
        defer { offset = data.count }
        return data.subdata(in: (data.startIndex + offset)..<data.endIndex)
    }
}
