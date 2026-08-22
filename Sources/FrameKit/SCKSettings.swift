/// Capture options for `SCKFrameSource` (T1-GFX-05). Not part of `FrameSource` (ISP).
public struct SCKSettings: Sendable, Equatable {
    /// Composite the system cursor into BGRA frames.
    public var showsCursor: Bool

    public init(showsCursor: Bool = true) {
        self.showsCursor = showsCursor
    }
}
