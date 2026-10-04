import Foundation

/// A point in the streamed picture, normalized to 0…1 on both axes (top-left origin).
/// Normalized so input never depends on the client's window size or the encoded size.
public struct Point01: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func clamped() -> Point01 {
        Point01(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

public enum MouseButton: Int, Codable, Sendable {
    case left = 0
    case right = 1
    case middle = 2
}

/// Raw values are macOS `CGScrollPhase`.
public enum ScrollPhase: Int, Codable, Sendable {
    case none = 0
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8
    case mayBegin = 128
}

/// Raw values are macOS `CGMomentumScrollPhase`.
public enum MomentumPhase: Int, Codable, Sendable {
    case none = 0
    case begin = 1
    case `continue` = 2
    case end = 3
}

/// T2-NAT-05: Mac-correct input. Keys are USB HID keyboard-page usages (what iPadOS reports as
/// `UIKey.keyCode`), so Cmd stays Cmd and Option stays Option. The host maps them to macOS keycodes.
public enum InputEvent: Codable, Equatable, Sendable {
    case key(usage: UInt16, down: Bool)
    case move(Point01)
    case button(MouseButton, down: Bool, at: Point01, clickCount: Int)
    /// Continuous (trackpad) scrolling in points, with phases so the Mac sees real gesture scrolling.
    case scroll(dx: Double, dy: Double, phase: ScrollPhase, momentum: MomentumPhase)
    /// Discrete mouse-wheel lines.
    case wheel(dx: Int, dy: Int)
    /// Window lost focus or the connection is closing: release every held key and button.
    case releaseAll
}

/// USB HID keyboard-page usages the client and host both care about by name.
public enum HIDUsage {
    public static let a: UInt16 = 0x04
    public static let digit1: UInt16 = 0x1E
    public static let digit9: UInt16 = 0x26
    public static let digit0: UInt16 = 0x27
    public static let leftBracket: UInt16 = 0x2F
    public static let rightBracket: UInt16 = 0x30
    public static let leftControl: UInt16 = 0xE0
    public static let leftShift: UInt16 = 0xE1
    public static let leftOption: UInt16 = 0xE2
    public static let leftCommand: UInt16 = 0xE3
    public static let rightControl: UInt16 = 0xE4
    public static let rightShift: UInt16 = 0xE5
    public static let rightOption: UInt16 = 0xE6
    public static let rightCommand: UInt16 = 0xE7

    public static func isModifier(_ usage: UInt16) -> Bool { (0xE0...0xE7).contains(usage) }
}
