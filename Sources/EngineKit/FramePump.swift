import FrameKit

/// Pulls `FrameSource.nextFrame()` and `Engine.push` under a 60 fps cap (T1-GFX-04).
/// Not a protocol: wiring only. `FrameSource` still has only `nextFrame()`.
public final class FramePump: @unchecked Sendable {
    private let source: any FrameSource
    private let engine: Engine
    private var pacer: FramePacer

    public init(source: any FrameSource, engine: Engine, pacer: FramePacer = FramePacer()) {
        self.source = source
        self.engine = engine
        self.pacer = pacer
    }

    /// `true` if a frame was pushed.
    @discardableResult
    public func pumpOnce(now: ContinuousClock.Instant = .now) async throws -> Bool {
        guard pacer.shouldEmit(at: now) else {
            return false
        }
        let frame = await source.nextFrame()
        try engine.push(frame)
        return true
    }
}
