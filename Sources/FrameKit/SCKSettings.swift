/// Capture options for `SCKFrameSource` (T1-GFX-05, T1-MON-02). Not part of `FrameSource` (ISP).
public struct SCKSettings: Sendable, Equatable {
    /// Composite the system cursor into BGRA frames.
    public var showsCursor: Bool
    /// Which Mac display to capture.
    public var display: DisplayChoice

    public init(showsCursor: Bool = true, display: DisplayChoice = .main) {
        self.showsCursor = showsCursor
        self.display = display
    }
}
