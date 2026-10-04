import Foundation
import ViewportProtocol

/// T2-NAT-05: after a trackpad scroll gesture ends, keep scrolling with decaying velocity so the
/// Mac sees momentum phases like a real trackpad (iPadOS does not deliver momentum deltas to apps).
public enum MomentumScroller {
    /// Decay per 1/60 s frame; matches UIScrollView's normal rate (0.998 per ms).
    public static let decayPerFrame = 0.967
    public static let stopSpeed = 12.0  // points per second
    public static let maxDuration = 2.5  // seconds

    /// Per-frame scroll deltas (points) after release at `velocity` (points per second).
    public static func deltas(velocityX: Double, velocityY: Double, frameInterval: Double = 1.0 / 60.0) -> [(dx: Double, dy: Double)] {
        var vx = velocityX
        var vy = velocityY
        var out: [(Double, Double)] = []
        var t = 0.0
        while (vx * vx + vy * vy).squareRoot() >= stopSpeed, t < maxDuration {
            out.append((vx * frameInterval, vy * frameInterval))
            vx *= decayPerFrame
            vy *= decayPerFrame
            t += frameInterval
        }
        return out
    }

    /// The input events for a momentum run: begin, continue…, end.
    public static func events(velocityX: Double, velocityY: Double) -> [InputEvent] {
        let d = deltas(velocityX: velocityX, velocityY: velocityY)
        guard !d.isEmpty else { return [] }
        var events: [InputEvent] = []
        for (i, step) in d.enumerated() {
            events.append(.scroll(dx: step.dx, dy: step.dy, phase: .none, momentum: i == 0 ? .begin : .continue))
        }
        events.append(.scroll(dx: 0, dy: 0, phase: .none, momentum: .end))
        return events
    }
}
