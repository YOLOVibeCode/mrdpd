import SwiftUI
import ViewportProtocol

/// A window showing one Mac display, with the display switcher on top.
struct ViewportScreen: View {
    @StateObject private var model: ViewportModel
    @EnvironmentObject private var windows: WindowRegistry
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.scenePhase) private var scenePhase
    private let onDisplay: (UInt32) -> Void
    private let onLeave: () -> Void

    init(link: PairingLink, savedDisplayID: UInt32?, onDisplay: @escaping (UInt32) -> Void, onLeave: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ViewportModel(link: link, preferredDisplayID: savedDisplayID))
        self.onDisplay = onDisplay
        self.onLeave = onLeave
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            RemoteSurface(model: model).ignoresSafeArea()
            ViewportHUD(
                model: model,
                onNewWindow: supportsMultipleWindows ? { openWindow(id: "viewport") } : nil,
                onLeave: {
                    model.disconnect()
                    onLeave()
                })
            status
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .defersSystemGestures(on: .all)
        .onAppear {
            let id = model.windowID
            model.avoidDisplays = { [weak windows] in windows?.displays(except: id) ?? [] }
            model.onDisplay = { [weak windows] display in
                windows?.set(id, display: display)
                onDisplay(display)
            }
        }
        .onDisappear {
            windows.set(model.windowID, display: nil)
            model.disconnect()
        }
        .onChange(of: scenePhase) { _, phase in model.sceneActive(phase == .active) }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .connected:
            EmptyView()
        case .waiting, .connecting:
            ProgressView("Connecting to \(model.hostName)…")
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxHeight: .infinity)
        case .failed(let reason):
            VStack(spacing: 12) {
                Text("Can't reach \(model.hostName)").font(.headline)
                Text(reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("Is `mrdpd-host serve` running on the Mac, and is this iPad on its network?")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Retry") { model.connect() }.buttonStyle(.borderedProminent)
                    Button("Back") { onLeave() }
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .frame(maxHeight: .infinity)
        }
    }
}

/// Top-center switcher: ‹ display › plus a menu; expands into thumbnails (T2-NAT-04).
/// Fades out after 3 s so it never covers the Mac's menu bar for long; the pointer at the top
/// edge, a three-finger tap, or Ctrl+Option+0 bring it back.
struct ViewportHUD: View {
    @ObservedObject var model: ViewportModel
    let onNewWindow: (() -> Void)?
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button { model.perform(.previous) } label: { Image(systemName: "chevron.left") }
                Button { model.pickerOpen.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "display")
                        Text(title).lineLimit(1)
                    }
                }
                Button { model.perform(.next) } label: { Image(systemName: "chevron.right") }
                Menu {
                    if let onNewWindow {
                        Button("New Window", systemImage: "macwindow.badge.plus", action: onNewWindow)
                    }
                    if let rtt = model.rtt {
                        Text("Round trip \(Int(rtt)) ms · \(model.fps) fps")
                    }
                    Button("Disconnect", systemImage: "xmark.circle", role: .destructive, action: onLeave)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            if model.pickerOpen {
                DisplayPicker(model: model)
            }
        }
        .padding(.top, 6)
        .opacity(model.hudVisible || model.pickerOpen ? 1 : 0)
        .allowsHitTesting(model.hudVisible || model.pickerOpen)
        .animation(.easeInOut(duration: 0.2), value: model.hudVisible)
    }

    private var title: String {
        guard let d = model.currentDisplay else { return model.hostName }
        return "\(d.index) · \(d.name)"
    }
}

struct DisplayPicker: View {
    @ObservedObject var model: ViewportModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(model.displays.sorted { $0.index < $1.index }) { display in
                    Button {
                        model.show(display.id)
                    } label: {
                        VStack(spacing: 6) {
                            thumbnail(display)
                                .frame(width: 220, height: 220 * display.frame.height / max(display.frame.width, 1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(display.id == model.currentDisplayID ? Color.accentColor : .clear, lineWidth: 3)
                                }
                            Text("\(display.index)  \(display.name)").font(.caption).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(display.index % 10)")), modifiers: [.control, .option])
                }
            }
            .padding(14)
        }
        .frame(maxWidth: 980)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    @ViewBuilder private func thumbnail(_ display: DisplayInfo) -> some View {
        if let image = model.thumbnails[display.id] {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
    }
}
