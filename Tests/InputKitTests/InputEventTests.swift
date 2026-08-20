import XCTest
@testable import InputKit

/// T1-IN-01: InputEvent is a value type with key/mouse equality.
/// Modifiers are scancode events (no bitmask, no keymap table).
final class InputEventTests: XCTestCase {
    func testIdenticalKeyDownEventsAreEqual() {
        let a = InputEvent.key(scancode: 0x1E, isExtended: false, isPressed: true)
        let b = InputEvent.key(scancode: 0x1E, isExtended: false, isPressed: true)
        XCTAssertEqual(a, b)
    }

    func testKeyDownIsNotEqualToKeyUp() {
        let down = InputEvent.key(scancode: 0x1E, isExtended: false, isPressed: true)
        let up = InputEvent.key(scancode: 0x1E, isExtended: false, isPressed: false)
        XCTAssertNotEqual(down, up)
    }

    func testExtendedFlagDistinguishesModifierEvents() {
        // Set-1 0x1D: left Ctrl vs right Ctrl (E0 prefix). Not a keymap (T1-IN-02).
        let leftCtrl = InputEvent.key(scancode: 0x1D, isExtended: false, isPressed: true)
        let rightCtrl = InputEvent.key(scancode: 0x1D, isExtended: true, isPressed: true)
        XCTAssertNotEqual(leftCtrl, rightCtrl)
    }

    func testIdenticalMouseMovesAreEqual() {
        let a = InputEvent.mouse(x: 10, y: 20, buttons: 0, wheel: 0)
        let b = InputEvent.mouse(x: 10, y: 20, buttons: 0, wheel: 0)
        XCTAssertEqual(a, b)
    }

    func testMouseEventsDifferWhenFieldsDiffer() {
        let base = InputEvent.mouse(x: 10, y: 20, buttons: 0b001, wheel: 0)
        XCTAssertNotEqual(base, InputEvent.mouse(x: 11, y: 20, buttons: 0b001, wheel: 0))
        XCTAssertNotEqual(base, InputEvent.mouse(x: 10, y: 20, buttons: 0b010, wheel: 0))
        XCTAssertNotEqual(base, InputEvent.mouse(x: 10, y: 20, buttons: 0b001, wheel: 120))
    }

    func testKeyEventIsNotEqualToMouseEvent() {
        let key = InputEvent.key(scancode: 0x1E, isExtended: false, isPressed: true)
        let mouse = InputEvent.mouse(x: 0, y: 0, buttons: 0, wheel: 0)
        XCTAssertNotEqual(key, mouse)
    }
}
