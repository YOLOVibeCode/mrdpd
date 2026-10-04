import CoreGraphics
import Foundation
import XCTest

@testable import HostKit
import ViewportProtocol

/// T1-GFX-08: frame-rate budget across viewports (spike R15).
final class EncodePolicyTests: XCTestCase {
    func testEveryoneGetsSixtyWhileEnginesSuffice() {
        XCTAssertEqual(EncodePolicy.allocate(["a", "b"], engines: 2), ["a": 60, "b": 60])
    }

    func testMostRecentKeepsSixtyAndOthersShareTheRest() {
        XCTAssertEqual(EncodePolicy.allocate(["a", "b", "c"], engines: 2), ["a": 60, "b": 30, "c": 30])
        XCTAssertEqual(EncodePolicy.allocate(["a", "b"], engines: 1), ["a": 60, "b": 10])
    }

    func testEngineCountByChip() {
        XCTAssertEqual(EncodePolicy.engineCount(cpuBrand: "Apple M4 Max"), 2)
        XCTAssertEqual(EncodePolicy.engineCount(cpuBrand: "Apple M2 Ultra"), 4)
        XCTAssertEqual(EncodePolicy.engineCount(cpuBrand: "Apple M4 Pro"), 1)
    }

    func testSchedulerTellsTheDemotedViewport() {
        let scheduler = EncodeScheduler(engines: 1)
        final class Box: @unchecked Sendable { var fps: [String: Int] = [:]; let lock = NSLock() }
        let box = Box()
        let a = UUID()
        let b = UUID()
        XCTAssertEqual(scheduler.register(a) { f in box.lock.withLock { box.fps["a"] = f } }, 60)
        XCTAssertEqual(scheduler.register(b) { f in box.lock.withLock { box.fps["b"] = f } }, 10)
        scheduler.touch(b)
        XCTAssertEqual(box.lock.withLock { box.fps }, ["a": 10, "b": 60])
        scheduler.unregister(b)
        XCTAssertEqual(scheduler.fps(a), 60)
    }
}

/// T2-NAT-05: native input → CGEvents (recorded, never posted).
final class NativeInputInjectorTests: XCTestCase {
    let sceptre = RectD(x: -629, y: -2160, width: 1600, height: 1200)

    func testCommandAKeepsCommandFlagOnTheLetter() {
        let poster = RecordingPoster()
        let injector = NativeInputInjector(poster: poster, repeatDelay: 10, repeatInterval: 10)
        injector.inject(.key(usage: HIDUsage.leftCommand, down: true), displayFrame: sceptre)
        injector.inject(.key(usage: HIDUsage.a, down: true), displayFrame: sceptre)
        injector.inject(.key(usage: HIDUsage.a, down: false), displayFrame: sceptre)
        injector.inject(.key(usage: HIDUsage.leftCommand, down: false), displayFrame: sceptre)
        let events = poster.all
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[1].getIntegerValueField(.keyboardEventKeycode), 0x00)
        XCTAssertTrue(events[1].flags.contains(.maskCommand))
        XCTAssertFalse(events[3].flags.contains(.maskCommand))
    }

    func testClickLandsOnTheMappedGlobalPointWithClickCount() {
        let poster = RecordingPoster()
        let injector = NativeInputInjector(poster: poster, repeatDelay: 10, repeatInterval: 10)
        injector.inject(.button(.left, down: true, at: Point01(x: 0.5, y: 0.5), clickCount: 2), displayFrame: sceptre)
        injector.inject(.move(Point01(x: 0.25, y: 0.5)), displayFrame: sceptre)
        injector.inject(.button(.left, down: false, at: Point01(x: 0.25, y: 0.5), clickCount: 2), displayFrame: sceptre)
        let events = poster.all
        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(events[0].location, CGPoint(x: 171, y: -1560))
        XCTAssertEqual(events[0].getIntegerValueField(.mouseEventClickState), 2)
        XCTAssertEqual(events[2].location, CGPoint(x: -229, y: -1560))
    }

    func testTrackpadScrollIsContinuousWithPhasesAndKeepsFractions() {
        let poster = RecordingPoster()
        let injector = NativeInputInjector(poster: poster, repeatDelay: 10, repeatInterval: 10)
        injector.inject(.scroll(dx: 0, dy: 2.6, phase: .began, momentum: .none), displayFrame: sceptre)
        injector.inject(.scroll(dx: 0, dy: 2.6, phase: .changed, momentum: .none), displayFrame: sceptre)
        let events = poster.all
        XCTAssertEqual(events.map(\.type), [.scrollWheel, .scrollWheel])
        XCTAssertEqual(events[0].getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        XCTAssertEqual(events[0].getIntegerValueField(.scrollWheelEventScrollPhase), Int64(ScrollPhase.began.rawValue))
        XCTAssertEqual(events[0].getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 2)
        XCTAssertEqual(events[1].getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 3)  // 0.6 + 2.6 carried over
    }

    func testReleaseAllLetsGoOfHeldKeysAndButtons() {
        let poster = RecordingPoster()
        let injector = NativeInputInjector(poster: poster, repeatDelay: 10, repeatInterval: 10)
        injector.inject(.key(usage: HIDUsage.leftShift, down: true), displayFrame: sceptre)
        injector.inject(.key(usage: HIDUsage.a, down: true), displayFrame: sceptre)
        injector.inject(.button(.right, down: true, at: Point01(x: 0.1, y: 0.1), clickCount: 1), displayFrame: sceptre)
        poster.clear()
        injector.inject(.releaseAll, displayFrame: sceptre)
        let types = poster.all.map(\.type)
        XCTAssertEqual(types.filter { $0 == .keyUp }.count, 1)  // the letter
        XCTAssertEqual(types.filter { $0 == .flagsChanged }.count, 1)  // Shift: modifier keys post flagsChanged
        XCTAssertTrue(types.contains(.rightMouseUp))
    }

    func testHeldKeyRepeatsAtTheMacRate() async throws {
        let poster = RecordingPoster()
        let injector = NativeInputInjector(poster: poster, repeatDelay: 0.05, repeatInterval: 0.02)
        injector.inject(.key(usage: HIDUsage.a, down: true), displayFrame: sceptre)
        try await Task.sleep(for: .milliseconds(200))
        injector.inject(.key(usage: HIDUsage.a, down: false), displayFrame: sceptre)
        let repeats = poster.all.filter { $0.getIntegerValueField(.keyboardEventAutorepeat) == 1 }
        XCTAssertGreaterThanOrEqual(repeats.count, 3)
        let count = poster.all.count
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(poster.all.count, count, "repeat must stop on key up")
    }
}

/// T2-NAT-02: paired-device store.
final class PairingStoreTests: XCTestCase {
    func testPairListRemoveAndPermissions() throws {
        let store = PairingStore(directory: temporaryDirectory())
        let a = try store.pair(name: "iPad")
        let b = try store.pair(name: "iPad mini")
        XCTAssertEqual(a.key.count, 32)
        XCTAssertNotEqual(a.key, b.key)
        XCTAssertEqual(try store.keys().count, 2)
        let perms = try FileManager.default.attributesOfItem(atPath: store.devicesFile.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertTrue(try store.remove(id: a.id))
        XCTAssertFalse(try store.remove(id: a.id))
        XCTAssertEqual(try store.devices().map(\.id), [b.id])
        XCTAssertEqual(try store.hostID(), try store.hostID())
    }
}
