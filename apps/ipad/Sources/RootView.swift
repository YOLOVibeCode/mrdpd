import SwiftUI
import ViewportProtocol

/// One window: pick (or auto-pick) a paired Mac, then show one of its displays.
struct RootView: View {
    @EnvironmentObject private var hosts: HostStore
    @SceneStorage("hostDeviceID") private var hostDeviceID = ""
    @SceneStorage("displayID") private var savedDisplayID = 0
    @State private var selected: PairedHost?
    @State private var pairing = false
    @State private var offered: PairingLink?

    var body: some View {
        Group {
            if let host = selected, let link = hosts.link(for: host) {
                ViewportScreen(
                    link: link,
                    savedDisplayID: Self.testDisplayID ?? (savedDisplayID == 0 ? nil : UInt32(savedDisplayID)),
                    onDisplay: { savedDisplayID = Int($0) },
                    onLeave: { selected = nil }
                )
                .id(host.id)
            } else if hosts.hosts.isEmpty {
                PairingView(onDone: nil)
            } else {
                HostListView(
                    onSelect: { host in
                        hostDeviceID = host.deviceID
                        selected = host
                    },
                    onPair: { pairing = true })
            }
        }
        .sheet(isPresented: $pairing) {
            PairingView(onDone: { pairing = false })
        }
        .onAppear(perform: autoSelect)
        .onChange(of: hosts.hosts) { _, _ in autoSelect() }
        .onOpenURL { url in
            // Camera-app QR scans open mrdpd://pair?… Any app or web page can open such a link, so the
            // owner confirms the Mac's name and address before a key is stored.
            guard let link = PairingLink(url: url.absoluteString) else { return }
            #if DEBUG
                if ProcessInfo.processInfo.environment["MRDPD_UI_TEST_AUTOPAIR"] == "1" {
                    _ = try? hosts.add(link)
                    return
                }
            #endif
            offered = link
        }
        .alert(
            "Pair with \(offered?.hostName ?? "this Mac")?",
            isPresented: Binding(get: { offered != nil }, set: { if !$0 { offered = nil } }),
            presenting: offered
        ) { link in
            Button("Pair") {
                _ = try? hosts.add(link)
                offered = nil
            }
            Button("Cancel", role: .cancel) { offered = nil }
        } message: { link in
            Text("\(link.address):\(String(link.port)). Only pair with a Mac you just ran `mrdpd-host pair` on.")
        }
    }

    /// Simulator tests pick the starting display (DEBUG only).
    private static var testDisplayID: UInt32? {
        #if DEBUG
            return ProcessInfo.processInfo.environment["MRDPD_UI_TEST_DISPLAY"].flatMap(UInt32.init)
        #else
            return nil
        #endif
    }

    private func autoSelect() {
        #if DEBUG
            // Simulator tests hand the pairing link in the launch environment (never on screen or in
            // logs) and start from a clean slate: forget earlier pairings, select the test Mac.
            if selected == nil, let s = ProcessInfo.processInfo.environment["MRDPD_UI_TEST_LINK"],
               let link = PairingLink(url: s)
            {
                for old in hosts.hosts where old.deviceID != link.deviceID { hosts.remove(old) }
                if let host = try? hosts.add(link) {
                    hostDeviceID = host.deviceID
                    selected = host
                }
                return
            }
        #endif
        guard selected == nil else { return }
        if let remembered = hosts.hosts.first(where: { $0.deviceID == hostDeviceID }) {
            selected = remembered
        } else if hosts.hosts.count == 1 {
            selected = hosts.hosts.first
            hostDeviceID = selected?.deviceID ?? ""
        }
    }
}

struct HostListView: View {
    @EnvironmentObject private var hosts: HostStore
    let onSelect: (PairedHost) -> Void
    let onPair: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(hosts.hosts) { host in
                    Button {
                        onSelect(host)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(host.hostName).font(.headline)
                            Text("\(host.address):\(String(host.port))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Forget", role: .destructive) { hosts.remove(host) }
                    }
                }
            }
            .navigationTitle("Macs")
            .toolbar {
                Button("Pair a Mac", systemImage: "plus", action: onPair)
            }
        }
    }
}
