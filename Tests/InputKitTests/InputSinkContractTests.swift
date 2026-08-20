import XCTest
@testable import InputKit

/// Canonical T1-IN-01 key-down delivered by the InputSink contract suite.
/// Set-1 scancode 0x1E; keymap tables are T1-IN-02 / stream S6.
let t1IN01ScriptedKeyDown = InputEvent.key(scancode: 0x1E, isExtended: false, isPressed: true)

/// Contract suite for any `InputSink` (T1-IN-01). Delivers one scancode key-down.
func testInputSinkContract(_ sink: any InputSink) {
    sink.handle(t1IN01ScriptedKeyDown)
}

final class InputSinkContractTests: XCTestCase {
    func testRecordingInputSinkRecordsOneKeyDown() {
        let sink = RecordingInputSink()
        testInputSinkContract(sink)
        XCTAssertEqual(sink.events, [t1IN01ScriptedKeyDown])
    }
}
