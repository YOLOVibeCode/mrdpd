import Foundation

/// Wire protocol version. Host and client must match exactly (no silent downgrades).
public enum ProtocolVersion {
    public static let current: UInt16 = 1
}

public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var pixels: Int { width * height }
}

/// A rectangle in Double coordinates. For displays: Quartz global points (origin top-left, Y down).
public struct RectD: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// One Mac display as the client sees it (T1-VP-01).
public struct DisplayInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: UInt32
    /// 1-based position in arrangement order; what the Ctrl+Option+N shortcuts address.
    public var index: Int
    public var name: String
    public var isBuiltin: Bool
    public var isMain: Bool
    /// Global points (Quartz, Y down).
    public var frame: RectD
    /// Backing (Retina) pixels.
    public var pixelSize: PixelSize

    public init(
        id: UInt32, index: Int, name: String, isBuiltin: Bool, isMain: Bool, frame: RectD, pixelSize: PixelSize
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.frame = frame
        self.pixelSize = pixelSize
    }
}

public struct Hello: Codable, Equatable, Sendable {
    public var protocolVersion: UInt16
    public var clientName: String
    /// The client window's drawable size in pixels.
    public var viewport: PixelSize
    public var preferredDisplayID: UInt32?
    public var focused: Bool

    public init(
        protocolVersion: UInt16 = ProtocolVersion.current, clientName: String, viewport: PixelSize,
        preferredDisplayID: UInt32? = nil, focused: Bool = true
    ) {
        self.protocolVersion = protocolVersion
        self.clientName = clientName
        self.viewport = viewport
        self.preferredDisplayID = preferredDisplayID
        self.focused = focused
    }
}

public struct Welcome: Codable, Equatable, Sendable {
    public var protocolVersion: UInt16
    public var hostName: String
    public var hostID: String
    public var displays: [DisplayInfo]

    public init(protocolVersion: UInt16 = ProtocolVersion.current, hostName: String, hostID: String, displays: [DisplayInfo]) {
        self.protocolVersion = protocolVersion
        self.hostName = hostName
        self.hostID = hostID
        self.displays = displays
    }
}

/// What the host is streaming to this viewport right now. A new `epoch` means the decoder must reset.
public struct StreamInfo: Codable, Equatable, Sendable {
    public var displayID: UInt32
    public var epoch: UInt32
    /// Encoded picture size; the source display's aspect ratio.
    public var contentSize: PixelSize
    public var fps: Int
    public var codec: String

    public init(displayID: UInt32, epoch: UInt32, contentSize: PixelSize, fps: Int, codec: String = "h264") {
        self.displayID = displayID
        self.epoch = epoch
        self.contentSize = contentSize
        self.fps = fps
        self.codec = codec
    }
}

public enum ClientMessage: Codable, Equatable, Sendable {
    case hello(Hello)
    /// Show this Mac display in this viewport (T1-VP-03).
    case subscribe(displayID: UInt32)
    case resize(PixelSize)
    /// This window is (or stopped being) the one the user is working in. Drives encode priority.
    case focus(Bool)
    case input(InputEvent)
    case requestKeyframe
    case requestThumbnails(maxWidth: Int)
    case ping(id: UInt32)
}

public enum HostMessage: Codable, Equatable, Sendable {
    case welcome(Welcome)
    case displays([DisplayInfo])
    case stream(StreamInfo)
    case pong(id: UInt32)
    case bye(reason: String)
}

public enum ControlCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static func frame(_ message: ClientMessage) throws -> WireFrame {
        WireFrame(kind: .control, payload: try encoder.encode(message))
    }

    public static func frame(_ message: HostMessage) throws -> WireFrame {
        WireFrame(kind: .control, payload: try encoder.encode(message))
    }

    public static func clientMessage(_ frame: WireFrame) throws -> ClientMessage {
        guard frame.kind == .control else { throw WireError.malformed("not a control frame") }
        return try JSONDecoder().decode(ClientMessage.self, from: frame.payload)
    }

    public static func hostMessage(_ frame: WireFrame) throws -> HostMessage {
        guard frame.kind == .control else { throw WireError.malformed("not a control frame") }
        return try JSONDecoder().decode(HostMessage.self, from: frame.payload)
    }
}
