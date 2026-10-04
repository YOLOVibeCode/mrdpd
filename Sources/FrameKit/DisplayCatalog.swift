import CoreGraphics

/// Which Mac display a one-monitor session shows (T1-MON-02).
public enum DisplayChoice: Sendable, Equatable {
    case main
    case letter(String)
}

/// Mac displays lettered A, B, C… left to right by global frame, then top to bottom (T1-MON-02).
/// Pure value type fed by `SCKFrameSource`. Not part of `FrameSource` (ISP).
public struct DisplayCatalog: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let letter: String
        public let displayID: UInt32
        /// Quartz global points: origin at the main display's top-left, Y down.
        public let frame: CGRect
        public let isMain: Bool
    }

    public let entries: [Entry]

    public init(displays: [(displayID: UInt32, frame: CGRect)], mainDisplayID: UInt32) {
        let ordered = displays.sorted { a, b in
            if a.frame.minX != b.frame.minX {
                return a.frame.minX < b.frame.minX
            }
            if a.frame.minY != b.frame.minY {
                return a.frame.minY < b.frame.minY
            }
            return a.displayID < b.displayID
        }
        entries = ordered.enumerated().map { index, display in
            Entry(
                letter: Self.letter(index),
                displayID: display.displayID,
                frame: display.frame,
                isMain: display.displayID == mainDisplayID
            )
        }
    }

    /// `.main` falls back to the first letter when the main display is not in the list.
    public func entry(for choice: DisplayChoice) -> Entry? {
        switch choice {
        case .main:
            return entries.first(where: \.isMain) ?? entries.first
        case let .letter(letter):
            let wanted = letter.uppercased()
            return entries.first { $0.letter == wanted }
        }
    }

    /// A…Z, then AA, AB…
    private static func letter(_ index: Int) -> String {
        var n = index
        var out = ""
        repeat {
            out = String(UnicodeScalar(UInt8(65 + n % 26))) + out
            n = n / 26 - 1
        } while n >= 0
        return out
    }
}
