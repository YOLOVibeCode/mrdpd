import CoreGraphics

/// Planned HID posts from one `InputEvent` (T1-IN-04). Not an `InputSink` method (ISP).
public enum Injection: Equatable, Sendable {
    public enum Mouse: Equatable, Sendable {
        case moved
        case leftDown, leftUp, leftDragged
        case rightDown, rightUp, rightDragged
        case otherDown, otherUp, otherDragged
    }

    case key(virtualKey: UInt16, down: Bool, flags: UInt64)
    case mouse(Mouse, x: Double, y: Double)
    case scroll(x: Double, y: Double, wheelLines: Int32)
}

public struct InjectionState: Equatable, Sendable {
    public var buttons: UInt32
    public var flags: CGEventFlags

    public init(buttons: UInt32 = 0, flags: CGEventFlags = []) {
        self.buttons = buttons
        self.flags = flags
    }
}

public enum InjectionPlan {
    public static func plan(
        _ event: InputEvent,
        map: DisplayMap,
        state: inout InjectionState
    ) -> [Injection] {
        switch event {
        case let .key(scancode, isExtended, isPressed):
            return planKey(scancode: scancode, isExtended: isExtended, isPressed: isPressed, state: &state)
        case let .mouse(x, y, buttons, wheel):
            return planMouse(x: x, y: y, buttons: buttons, wheel: wheel, map: map, state: &state)
        }
    }

    private static func planKey(
        scancode: UInt16,
        isExtended: Bool,
        isPressed: Bool,
        state: inout InjectionState
    ) -> [Injection] {
        guard let vk = UsKeymap.virtualKeyCode(scancode: scancode, isExtended: isExtended) else {
            return []
        }
        applyModifier(vk: vk, down: isPressed, state: &state)
        return [.key(virtualKey: vk, down: isPressed, flags: state.flags.rawValue)]
    }

    private static func applyModifier(vk: UInt16, down: Bool, state: inout InjectionState) {
        let flag: CGEventFlags?
        switch vk {
        case 0x38, 0x3C: flag = .maskShift
        case 0x3B, 0x3E: flag = .maskControl
        case 0x3A, 0x3D: flag = .maskAlternate
        case 0x37, 0x36: flag = .maskCommand
        case 0x39: flag = .maskAlphaShift
        default: flag = nil
        }
        guard let flag else {
            return
        }
        if down {
            state.flags.insert(flag)
        } else {
            state.flags.remove(flag)
        }
    }

    private static func planMouse(
        x: Int32,
        y: Int32,
        buttons: UInt32,
        wheel: Int16,
        map: DisplayMap,
        state: inout InjectionState
    ) -> [Injection] {
        let loc = map.cgLocation(rdpX: x, rdpY: y)
        var out: [Injection] = []
        let prev = state.buttons
        out.append(motion(buttons: prev, x: loc.x, y: loc.y))
        let pairs: [(UInt32, Injection.Mouse, Injection.Mouse)] = [
            (1, .leftDown, .leftUp),
            (2, .rightDown, .rightUp),
            (4, .otherDown, .otherUp),
        ]
        for (bit, downKind, upKind) in pairs {
            let was = prev & bit != 0
            let now = buttons & bit != 0
            if !was && now {
                out.append(.mouse(downKind, x: loc.x, y: loc.y))
            } else if was && !now {
                out.append(.mouse(upKind, x: loc.x, y: loc.y))
            }
        }
        state.buttons = buttons
        if wheel != 0 {
            let q = Int32(wheel) / 120
            let lines: Int32 = q != 0 ? q : (wheel > 0 ? 1 : -1)
            out.append(.scroll(x: loc.x, y: loc.y, wheelLines: lines))
        }
        return out
    }

    private static func motion(buttons: UInt32, x: Double, y: Double) -> Injection {
        if buttons & 1 != 0 {
            return .mouse(.leftDragged, x: x, y: y)
        }
        if buttons & 2 != 0 {
            return .mouse(.rightDragged, x: x, y: y)
        }
        if buttons & 4 != 0 {
            return .mouse(.otherDragged, x: x, y: y)
        }
        return .mouse(.moved, x: x, y: y)
    }
}
