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
}
