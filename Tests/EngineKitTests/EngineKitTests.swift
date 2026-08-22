import EngineKit
import FrameKit
import InputKit
import XCTest

final class EngineKitTests: XCTestCase {
    private static let gate = NSLock()
    private var engine: Engine?

    override func invokeTest() {
        Self.gate.lock()
        defer { Self.gate.unlock() }
        super.invokeTest()
    }

    override func tearDown() {
        engine?.stop()
        engine = nil
        super.tearDown()
    }

    func testAbiVersionIsOne() throws {
        let engine = try Engine(dylibPath: StubEngineDylib.path())
        self.engine = engine
        XCTAssertEqual(engine.abiVersion, 1)
    }

    func testStartStopIdempotentStop() throws {
        let engine = try Engine(dylibPath: StubEngineDylib.path())
        self.engine = engine
        let sink = RecordingInputSink()
        try engine.start(sink: sink)
        engine.stop()
        engine.stop()
        try engine.start(sink: sink)
        engine.stop()
    }

    func testPushSyntheticFrameSurvivesPoisonAfterReturn() async throws {
        let engine = try Engine(dylibPath: StubEngineDylib.path())
        self.engine = engine
        try engine.start(sink: RecordingInputSink())

        let source = SyntheticFrameSource()
        let frame = await source.nextFrame()
        var poisonable = frame.pixels
        let original = poisonable
        let live = Frame(
            width: frame.width,
            height: frame.height,
            stride: frame.stride,
            pixels: poisonable,
            dirtyRects: frame.dirtyRects
        )
        try engine.push(live)
        for i in poisonable.indices {
            poisonable[i] = 0xA5
        }
        XCTAssertEqual(poisonable.first, 0xA5)
        let stored = try engine.copyLastFramePixelsForTests()
        XCTAssertEqual(stored, original)
        XCTAssertFalse(stored.allSatisfy { $0 == 0xA5 })
    }

    /// T1-GFX-01 M2: EngineKit pushes a 1080p `SyntheticFrameSource` frame over ABI v1 (no new symbols).
    func testPush1080pPatternSurvivesPoisonAfterReturn() async throws {
        let engine = try Engine(dylibPath: StubEngineDylib.path())
        self.engine = engine
        try engine.start(
            config: EngineConfig(desktopWidth: 1920, desktopHeight: 1080),
            sink: RecordingInputSink()
        )

        let source = SyntheticFrameSource(frame: SyntheticFrameSource.pattern1080p)
        let frame = await source.nextFrame()
        XCTAssertEqual(frame.width, 1920)
        XCTAssertEqual(frame.height, 1080)
        var poisonable = frame.pixels
        let original = poisonable
        let live = Frame(
            width: frame.width,
            height: frame.height,
            stride: frame.stride,
            pixels: poisonable,
            dirtyRects: frame.dirtyRects
        )
        try engine.push(live)
        for i in poisonable.indices {
            poisonable[i] = 0xA5
        }
        let nbytes = Int(1920 * 1080 * 4)
        let stored = try engine.copyLastFramePixelsForTests(capacity: nbytes)
        XCTAssertEqual(stored.count, nbytes)
        XCTAssertEqual(stored, original)
        XCTAssertFalse(stored.allSatisfy { $0 == 0xA5 })
    }

    func testScriptedMouseHopsToRecordingInputSink() throws {
        let engine = try Engine(dylibPath: StubEngineDylib.path())
        self.engine = engine
        let sink = RecordingInputSink()
        let hop = DispatchQueue(label: "mrdpd.test.hop")
        let hopped = expectation(description: "callback on hop queue")
        hop.async { /* warm */ }

        let engineOnHop = try Engine(dylibPath: StubEngineDylib.path(), callbackQueue: hop)
        self.engine = engineOnHop
        try engineOnHop.start(sink: sink)
        try engineOnHop.scriptMouseForTests(x: 12, y: 34, buttons: 1, wheel: -1)
        hop.async { hopped.fulfill() }
        wait(for: [hopped], timeout: 1.0)
        XCTAssertEqual(sink.events, [.mouse(x: 12, y: 34, buttons: 1, wheel: -1)])
        engineOnHop.stop()
    }

    /// T1-IN-01: scripted scancode down/up hops onto `callbackQueue` into `RecordingInputSink`.
    func testScriptedKeySequenceHopsToRecordingInputSink() throws {
        let sink = RecordingInputSink()
        let hop = DispatchQueue(label: "mrdpd.test.hop.key")
        let hopped = expectation(description: "key callback on hop queue")
        hop.async { /* warm */ }

        let engineOnHop = try Engine(dylibPath: StubEngineDylib.path(), callbackQueue: hop)
        self.engine = engineOnHop
        try engineOnHop.start(sink: sink)
        try engineOnHop.scriptKeyForTests(scancode: 0x1E, isExtended: false, isPressed: true)
        try engineOnHop.scriptKeyForTests(scancode: 0x1E, isExtended: false, isPressed: false)
        hop.async { hopped.fulfill() }
        wait(for: [hopped], timeout: 1.0)
        XCTAssertEqual(sink.events, [
            .key(scancode: 0x1E, isExtended: false, isPressed: true),
            .key(scancode: 0x1E, isExtended: false, isPressed: false),
        ])
        engineOnHop.stop()
    }

    /// T1-GFX-04: pacer drops a second pump inside 1/60 s; first pump copies through ABI v1.
    func testPacedPumpDropsSecondCallInsideInterval() async throws {
        let engine = try Engine(dylibPath: StubEngineDylib.path())
        self.engine = engine
        try engine.start(sink: RecordingInputSink())
        let pump = FramePump(source: SyntheticFrameSource(), engine: engine)
        let t0 = ContinuousClock.now
        let first = try await pump.pumpOnce(now: t0)
        XCTAssertTrue(first, "T1-GFX-04: first emit")
        let stored = try engine.copyLastFramePixelsForTests()
        XCTAssertFalse(stored.isEmpty, "T1-GFX-01: pump pushed pixels")
        let second = try await pump.pumpOnce(now: t0.advanced(by: .milliseconds(1)))
        XCTAssertFalse(second, "T1-GFX-04: cap 60 fps")
    }

    /// T1-PERF-03: idle bitrate is a live-session measurement, not CI.
    func testPerf03IdleBitrateIsManualInterop() throws {
        throw XCTSkip("T1-PERF-03: idle < 50 kbit/s on `just serve` + client; see docs/bench.md")
    }

    /// T1-PERF-04: idle CPU is a live-session measurement, not CI.
    func testPerf04IdleCpuIsManualInterop() throws {
        throw XCTSkip("T1-PERF-04: CPU < 40% of one P-core idle 1080p; see docs/bench.md")
    }
}
