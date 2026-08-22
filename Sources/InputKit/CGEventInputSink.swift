import ApplicationServices
import CoreGraphics
import Foundation

/// Posts `InputEvent` as HID `CGEvent`s (T1-IN-04). `InputSink` still has only `handle(_:)`.
public final class CGEventInputSink: InputSink {
    public static var postEventAllowed: Bool {
        AXIsProcessTrusted()
    }

    private let map: DisplayMap
    private var state = InjectionState()

    public init(map: DisplayMap) throws {
        guard Self.postEventAllowed else {
            throw CGEventInputSinkError.denied
        }
        self.map = map
    }

    public func handle(_ event: InputEvent) {
        let items = InjectionPlan.plan(event, map: map, state: &state)
        for item in items {
            post(item)
        }
    }

    private func post(_ item: Injection) {
        switch item {
        case let .key(virtualKey, down, flags):
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(virtualKey),
                keyDown: down
            ) else {
                return
            }
            event.flags = CGEventFlags(rawValue: flags)
            event.post(tap: .cghidEventTap)
        case let .mouse(kind, x, y):
            let (type, button) = Self.mouseBits(kind)
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: button
            ) else {
                return
            }
            event.post(tap: .cghidEventTap)
        case let .scroll(x, y, wheelLines):
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: wheelLines,
                wheel2: 0,
                wheel3: 0
            ) else {
                return
            }
            event.location = CGPoint(x: x, y: y)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func mouseBits(_ kind: Injection.Mouse) -> (CGEventType, CGMouseButton) {
        switch kind {
        case .moved: return (.mouseMoved, .left)
        case .leftDown: return (.leftMouseDown, .left)
        case .leftUp: return (.leftMouseUp, .left)
        case .leftDragged: return (.leftMouseDragged, .left)
        case .rightDown: return (.rightMouseDown, .right)
        case .rightUp: return (.rightMouseUp, .right)
        case .rightDragged: return (.rightMouseDragged, .right)
        case .otherDown: return (.otherMouseDown, .center)
        case .otherUp: return (.otherMouseUp, .center)
        case .otherDragged: return (.otherMouseDragged, .center)
        }
    }
}

public enum CGEventInputSinkError: Error {
    case denied
}
