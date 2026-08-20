/// Keyboard or mouse event at the InputSink boundary (T1-IN-01).
///
/// Key fields match ABI `MrdpdKeyEvent`: RDP scancode, extended (E0) flag, press/release.
/// Modifiers are ordinary scancode events, not a bitmask. Mouse fields match
/// `MrdpdMouseEvent` (virtual-desktop pixels; buttons bit0 left, bit1 right, bit2 middle;
/// `wheel` is vertical only).
public enum InputEvent: Equatable, Sendable {
    case key(scancode: UInt16, isExtended: Bool, isPressed: Bool)
    case mouse(x: Int32, y: Int32, buttons: UInt32, wheel: Int16)
}
