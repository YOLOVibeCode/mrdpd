import XCTest
import CoreGraphics
import InputKit

/// T1-IN-04 / T1-IN-01: plan CGEvent posts from `InputEvent`. Not extra `InputSink` methods.
final class InjectionPlanTests: XCTestCase {
    private let map = DisplayMap(
        originX: 0,
        originY: 0,
        pointWidth: 100,
        pointHeight: 100,
        pixelWidth: 100,
        pixelHeight: 100
    )

    func testUnknownScancodeIsDropped() {
        var state = InjectionState()
        let out = InjectionPlan.plan(
            .key(scancode: 0xFF, isExtended: false, isPressed: true),
            map: map,
            state: &state
        )
        XCTAssertTrue(out.isEmpty, "T1-IN-02: unknown scancode")
    }

    func testAKeyDownAndUp() {
        var state = InjectionState()
        let down = InjectionPlan.plan(
            .key(scancode: 0x1E, isExtended: false, isPressed: true),
            map: map,
            state: &state
        )
        let up = InjectionPlan.plan(
            .key(scancode: 0x1E, isExtended: false, isPressed: false),
            map: map,
            state: &state
        )
        XCTAssertEqual(down, [.key(virtualKey: 0x00, down: true, flags: 0)])
        XCTAssertEqual(up, [.key(virtualKey: 0x00, down: false, flags: 0)])
    }

    func testCommandThenACarriesCommandFlag() {
        var state = InjectionState()
        _ = InjectionPlan.plan(
            .key(scancode: 0x5B, isExtended: true, isPressed: true),
            map: map,
            state: &state
        )
        let a = InjectionPlan.plan(
            .key(scancode: 0x1E, isExtended: false, isPressed: true),
            map: map,
            state: &state
        )
        XCTAssertEqual(
            a,
            [.key(virtualKey: 0x00, down: true, flags: CGEventFlags.maskCommand.rawValue)],
            "T1-IN-04: Cmd held"
        )
    }

    func testMouseMoveAtMappedPoint() {
        var state = InjectionState()
        let out = InjectionPlan.plan(
            .mouse(x: 10, y: 20, buttons: 0, wheel: 0),
            map: map,
            state: &state
        )
        XCTAssertEqual(out, [.mouse(.moved, x: 10, y: 20)])
    }

    func testLeftButtonDownUp() {
        var state = InjectionState()
        let down = InjectionPlan.plan(
            .mouse(x: 1, y: 1, buttons: 1, wheel: 0),
            map: map,
            state: &state
        )
        let up = InjectionPlan.plan(
            .mouse(x: 1, y: 1, buttons: 0, wheel: 0),
            map: map,
            state: &state
        )
        XCTAssertTrue(down.contains(.mouse(.leftDown, x: 1, y: 1)), "T1-IN-03: left down")
        XCTAssertTrue(up.contains(.mouse(.leftUp, x: 1, y: 1)), "T1-IN-03: left up")
    }

    func testMoveWhileLeftHeldIsDragged() {
        var state = InjectionState()
        _ = InjectionPlan.plan(
            .mouse(x: 0, y: 0, buttons: 1, wheel: 0),
            map: map,
            state: &state
        )
        let drag = InjectionPlan.plan(
            .mouse(x: 5, y: 5, buttons: 1, wheel: 0),
            map: map,
            state: &state
        )
        XCTAssertTrue(drag.contains(.mouse(.leftDragged, x: 5, y: 5)), "T1-IN-03: drag")
    }

    func testVerticalWheel120IsOneLine() {
        var state = InjectionState()
        let out = InjectionPlan.plan(
            .mouse(x: 0, y: 0, buttons: 0, wheel: 120),
            map: map,
            state: &state
        )
        XCTAssertTrue(out.contains(.scroll(x: 0, y: 0, wheelLines: 1)), "T1-IN-03: wheel")
    }
}
