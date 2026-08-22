/// T1-GFX-04 frame pacing. Cap 60 fps. Not a `FrameSource` method (ISP).
public struct FramePacer: Sendable {
    public let maxFPS: Int
    public let minInterval: Duration
    private var lastEmit: ContinuousClock.Instant?

    public init(maxFPS: Int = 60) {
        self.maxFPS = max(1, maxFPS)
        self.minInterval = Duration.nanoseconds(1_000_000_000 / Int64(self.maxFPS))
        self.lastEmit = nil
    }

    public mutating func shouldEmit(at now: ContinuousClock.Instant = .now) -> Bool {
        if let last = lastEmit, now < last.advanced(by: minInterval) {
            return false
        }
        lastEmit = now
        return true
    }
}
