import SwiftUI

/// mrdpd for iPad (ADR 0008): each window is one viewport onto one Mac display. Put one window
/// on the iPad screen and another on the external monitor (Stage Manager) to see two at once.
@main
struct MrdpdApp: App {
    @StateObject private var hosts = HostStore()
    @StateObject private var windows = WindowRegistry()

    var body: some Scene {
        WindowGroup(id: "viewport") {
            RootView()
                .environmentObject(hosts)
                .environmentObject(windows)
        }
        .commands {
            // Keep Cmd+N and friends for the Mac, not for this app.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
        }
    }
}

/// Which Mac display each open window shows, so a new window picks a different one.
@MainActor
final class WindowRegistry: ObservableObject {
    @Published private(set) var shown: [UUID: UInt32] = [:]

    func set(_ window: UUID, display: UInt32?) {
        shown[window] = display
    }

    func displays(except window: UUID) -> Set<UInt32> {
        Set(shown.filter { $0.key != window }.values)
    }
}
