import XCTest
import FrameKit

/// T1-GFX-04: cap 60 fps. Not a `FrameSource` method (ISP).
final class FramePacerTests: XCTestCase {
    func testFirstEmitIsAllowed() {
        var pacer = FramePacer(maxFPS: 60)
        let t0 = ContinuousClock.now
        XCTAssertTrue(pacer.shouldEmit(at: t0), "T1-GFX-04: first frame")
    }

    func testSecondEmitInsideMinIntervalIsDropped() {
        var pacer = FramePacer(maxFPS: 60)
        let t0 = ContinuousClock.now
        XCTAssertTrue(pacer.shouldEmit(at: t0))
        XCTAssertFalse(
            pacer.shouldEmit(at: t0.advanced(by: .milliseconds(1))),
            "T1-GFX-04: cap 60 fps"
        )
    }

    func testEmitAfterMinIntervalIsAllowed() {
        var pacer = FramePacer(maxFPS: 60)
        let t0 = ContinuousClock.now
        XCTAssertTrue(pacer.shouldEmit(at: t0))
        XCTAssertTrue(
            pacer.shouldEmit(at: t0.advanced(by: .milliseconds(17))),
            "T1-GFX-04: 1/60 s elapsed"
        )
    }

    /// T1-PERF-01: synthetic 1080p path can emit ≥ 30 fps when the clock advances with the pacer.
    func testAllowsAtLeast30FpsWhenClockAdvances() {
        var pacer = FramePacer(maxFPS: 60)
        var now = ContinuousClock.now
        var n = 0
        for _ in 0..<60 {
            if pacer.shouldEmit(at: now) {
                n += 1
            }
            now = now.advanced(by: .milliseconds(16))
        }
        XCTAssertGreaterThanOrEqual(n, 30, "T1-PERF-01: ≥ 30 emits / 60 paced slots")
        XCTAssertLessThanOrEqual(n, 60, "T1-GFX-04: never above 60")
    }
}
