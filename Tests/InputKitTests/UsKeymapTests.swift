import XCTest
@testable import InputKit

/// T1-IN-02: RDP Set-1 scancode → macOS `kVK_*`. Pure data. Not an `InputSink` method.
final class UsKeymapTests: XCTestCase {
    func testAMapsToAnsiA() {
        XCTAssertEqual(UsKeymap.virtualKeyCode(scancode: 0x1E, isExtended: false), 0x00)
    }

    func testUnknownScancodeIsNil() {
        XCTAssertNil(UsKeymap.virtualKeyCode(scancode: 0xFF, isExtended: false))
        XCTAssertNil(UsKeymap.virtualKeyCode(scancode: 0x01, isExtended: true))
    }

    func testLeftAndRightControlDiffer() {
        XCTAssertEqual(UsKeymap.virtualKeyCode(scancode: 0x1D, isExtended: false), 0x3B)
        XCTAssertEqual(UsKeymap.virtualKeyCode(scancode: 0x1D, isExtended: true), 0x3E)
    }

    func testUsLettersDigitsModifiersAndArrows() {
        let cases: [(UInt16, Bool, UInt16, String)] = [
            (0x01, false, 0x35, "Esc"),
            (0x0E, false, 0x33, "Backspace"),
            (0x0F, false, 0x30, "Tab"),
            (0x1C, false, 0x24, "Return"),
            (0x39, false, 0x31, "Space"),
            (0x3A, false, 0x39, "CapsLock"),
            (0x2A, false, 0x38, "Shift"),
            (0x36, false, 0x3C, "RightShift"),
            (0x38, false, 0x3A, "Option"),
            (0x38, true, 0x3D, "RightOption"),
            (0x5B, true, 0x37, "Command"),
            (0x5C, true, 0x36, "RightCommand"),
            (0x4B, true, 0x7B, "LeftArrow"),
            (0x4D, true, 0x7C, "RightArrow"),
            (0x50, true, 0x7D, "DownArrow"),
            (0x48, true, 0x7E, "UpArrow"),
            (0x10, false, 0x0C, "Q"),
            (0x11, false, 0x0D, "W"),
            (0x12, false, 0x0E, "E"),
            (0x1F, false, 0x01, "S"),
            (0x02, false, 0x12, "1"),
            (0x0B, false, 0x1D, "0"),
            (0x3B, false, 0x7A, "F1"),
            (0x44, false, 0x6D, "F10"),
            (0x57, false, 0x67, "F11"),
            (0x58, false, 0x6F, "F12"),
            (0x53, true, 0x75, "ForwardDelete"),
            (0x1C, true, 0x4C, "KeypadEnter"),
            (0x52, false, 0x52, "Keypad0"),
        ]
        for (sc, ext, vk, name) in cases {
            XCTAssertEqual(
                UsKeymap.virtualKeyCode(scancode: sc, isExtended: ext),
                vk,
                "T1-IN-02 \(name) sc=0x\(String(sc, radix: 16)) ext=\(ext)"
            )
        }
    }

    /// T1-IN-01 sequence still uses `InputSink.handle` only; keymap is a lookup after record.
    func testRecordedSequenceMapsThroughUsKeymap() {
        let sink = RecordingInputSink()
        let seq: [InputEvent] = [
            .key(scancode: 0x1E, isExtended: false, isPressed: true),
            .key(scancode: 0x1E, isExtended: false, isPressed: false),
            .mouse(x: 100, y: 200, buttons: 1, wheel: 0),
        ]
        for event in seq {
            sink.handle(event)
        }
        XCTAssertEqual(sink.events, seq)
        XCTAssertEqual(
            sink.events.compactMap { UsKeymap.virtualKeyCode(for: $0) },
            [0x00, 0x00]
        )
    }
}
