import Foundation

/// T1-VP-03 / T2-NAT-04: display-switch shortcuts. Ctrl+Option+1…9 picks display N,
/// Ctrl+Option+[ and ] step through the arrangement, Ctrl+Option+0 opens the picker.
/// Shared so the native client and (later) the RDP host interpret them identically.
public enum SwitchAction: Equatable, Sendable {
    case display(index: Int)
    case previous
    case next
    case picker
}

public struct SwitchShortcuts: Sendable {
    private var held: Set<UInt16> = []

    public init() {}

    /// Feed every key event. Returns an action when this key-down completes a shortcut; the caller
    /// must then swallow the key (and its matching key-up) instead of sending it to the Mac.
    public mutating func handle(usage: UInt16, down: Bool) -> SwitchAction? {
        guard down else {
            held.remove(usage)
            return nil
        }
        defer { held.insert(usage) }
        let control = held.contains(HIDUsage.leftControl) || held.contains(HIDUsage.rightControl)
        let option = held.contains(HIDUsage.leftOption) || held.contains(HIDUsage.rightOption)
        let command = held.contains(HIDUsage.leftCommand) || held.contains(HIDUsage.rightCommand)
        let shift = held.contains(HIDUsage.leftShift) || held.contains(HIDUsage.rightShift)
        guard control, option, !command, !shift else { return nil }
        switch usage {
        case HIDUsage.digit1...HIDUsage.digit9: return .display(index: Int(usage - HIDUsage.digit1) + 1)
        case HIDUsage.digit0: return .picker
        case HIDUsage.leftBracket: return .previous
        case HIDUsage.rightBracket: return .next
        default: return nil
        }
    }

    /// The display to show after `action`, given the displays in arrangement order.
    public static func target(_ action: SwitchAction, current: UInt32?, displays: [DisplayInfo]) -> UInt32? {
        let ordered = displays.sorted { $0.index < $1.index }
        guard !ordered.isEmpty else { return nil }
        let position = ordered.firstIndex { $0.id == current }
        switch action {
        case .display(let index):
            return ordered.first { $0.index == index }?.id
        case .next:
            guard let p = position else { return ordered.first?.id }
            return ordered[(p + 1) % ordered.count].id
        case .previous:
            guard let p = position else { return ordered.last?.id }
            return ordered[(p - 1 + ordered.count) % ordered.count].id
        case .picker:
            return nil
        }
    }
}
