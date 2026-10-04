import CoreGraphics
import XCTest

@testable import InputKit

/// T2-NAT-05: HID usage → macOS virtual keycode.
final class HidKeymapTests: XCTestCase {
    func testLettersDigitsAndPunctuation() {
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0x04), 0x00)  // a → kVK_ANSI_A
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0x1D), 0x06)  // z
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0x1E), 0x12)  // 1
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0x27), 0x1D)  // 0
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0x35), 0x32)  // `
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0x2A), 0x33)  // backspace → kVK_Delete
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0x4C), 0x75)  // forward delete
    }

    func testEveryLetterAndDigitIsMappedOnce() {
        let codes = (0x04...0x27).compactMap { HidKeymap.virtualKeyCode(usage: UInt16($0)) }
        XCTAssertEqual(codes.count, 36)
        XCTAssertEqual(Set(codes).count, 36)
    }

    func testModifiersCarrySideBits() {
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0xE3), 0x37)  // left Command
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0xE7), 0x36)  // right Command
        XCTAssertTrue(HidKeymap.modifierFlags(usage: 0xE3)!.contains(.maskCommand))
        XCTAssertTrue(HidKeymap.modifierFlags(usage: 0xE2)!.contains(.maskAlternate))
        XCTAssertNotEqual(HidKeymap.modifierFlags(usage: 0xE1), HidKeymap.modifierFlags(usage: 0xE5))
        XCTAssertNil(HidKeymap.modifierFlags(usage: 0x04))
    }

    func testArrowsLookLikeAnAppleKeyboard() {
        XCTAssertEqual(HidKeymap.virtualKeyCode(usage: 0x52), 0x7E)  // up
        XCTAssertEqual(HidKeymap.intrinsicFlags(usage: 0x52), [.maskNumericPad, .maskSecondaryFn])
        XCTAssertEqual(HidKeymap.intrinsicFlags(usage: 0x04), [])
    }

    func testUnknownUsageIsNil() {
        XCTAssertNil(HidKeymap.virtualKeyCode(usage: 0x00))
        XCTAssertNil(HidKeymap.virtualKeyCode(usage: 0xFF))
    }
}
