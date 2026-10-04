import CoreMedia
import Foundation
import XCTest

import ViewportProtocol
@testable import ViewportClient

/// T1-GFX-07 client side and T2-NAT-05 momentum.
final class H264SampleBuilderTests: XCTestCase {
    // A real 64×64 H.264 SPS/PPS pair (Baseline, from VideoToolbox) is not needed to test the
    // gating logic: delta frames before a keyframe must be refused.
    func testDeltaBeforeKeyframeAsksForKeyframe() {
        var b = H264SampleBuilder()
        let delta = VideoPacket(
            epoch: 1, isKeyframe: false, captureTimeNanos: 0, width: 64, height: 64, parameterSets: [],
            avcc: Data([0, 0, 0, 1, 0x41]))
        guard case .needKeyframe = b.make(delta) else { return XCTFail("delta before keyframe must not decode") }
    }

    func testGarbageParameterSetsAreRejected() {
        var b = H264SampleBuilder()
        let key = VideoPacket(
            epoch: 1, isKeyframe: true, captureTimeNanos: 0, width: 64, height: 64,
            parameterSets: [Data([1, 2, 3]), Data([4, 5])], avcc: Data([0, 0, 0, 1, 0x65]))
        guard case .needKeyframe = b.make(key) else { return XCTFail("bad SPS/PPS must not produce a format") }
    }
}

final class MomentumScrollerTests: XCTestCase {
    func testMomentumDecaysAndEnds() {
        let events = MomentumScroller.events(velocityX: 0, velocityY: 1200)
        XCTAssertGreaterThan(events.count, 10)
        guard case .scroll(_, let firstDY, .none, .begin) = events.first! else { return XCTFail("starts with begin") }
        guard case .scroll(0, 0, .none, .end) = events.last! else { return XCTFail("ends with end") }
        guard case .scroll(_, let lastDY, .none, .continue) = events[events.count - 2] else { return XCTFail("continues") }
        XCTAssertGreaterThan(firstDY, lastDY)
        XCTAssertEqual(firstDY, 20, accuracy: 0.001)
    }

    func testSlowReleaseHasNoMomentum() {
        XCTAssertTrue(MomentumScroller.events(velocityX: 3, velocityY: 4).isEmpty)
    }
}
