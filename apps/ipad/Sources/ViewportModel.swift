import AVFoundation
import SwiftUI
import UIKit
import ViewportClient
import ViewportProtocol

enum CursorUpdate {
    case shape(UIImage, hotspot: CGPoint, size: CGSize)
    case visible(Bool)
}

/// One window's connection to the Mac: state for SwiftUI, input from `RemoteView`, video straight
/// to the renderer (never through the main actor).
@MainActor
final class ViewportModel: ObservableObject {
    enum Phase: Equatable {
        case waiting
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var phase: Phase = .waiting
    @Published private(set) var hostName: String
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var currentDisplayID: UInt32?
    @Published private(set) var contentSize: CGSize = .zero
    @Published private(set) var fps = 0
    @Published private(set) var rtt: Double?
    @Published private(set) var thumbnails: [UInt32: UIImage] = [:]
    @Published private(set) var hudVisible = true
    @Published var pickerOpen = false {
        didSet {
            if pickerOpen { startThumbnails() } else { stopThumbnails() }
            revealHUD()
        }
    }

    let link: PairingLink
    let windowID = UUID()
    let video = VideoOutput()
    var cursorChanged: ((CursorUpdate) -> Void)?
    /// "2 · Sceptre Z27 (2)" whenever the shown display changes (accessibility value, UI tests).
    var displayLabelChanged: ((String) -> Void)?
    var avoidDisplays: () -> Set<UInt32> = { [] }
    var onDisplay: (UInt32) -> Void = { _ in }

    private var preferredDisplayID: UInt32?
    private var connection: ViewportConnection?
    private var viewport: PixelSize?
    private var pendingResize: Task<Void, Never>?
    private var hideHUD: Task<Void, Never>?
    private var thumbnailTimer: Timer?
    private var shortcuts = SwitchShortcuts()
    private var swallowed: Set<UInt16> = []
    private var focused = true
    private var checkedForDuplicate = false

    init(link: PairingLink, preferredDisplayID: UInt32?) {
        self.link = link
        self.preferredDisplayID = preferredDisplayID
        hostName = link.hostName
    }

    var currentDisplay: DisplayInfo? { displays.first { $0.id == currentDisplayID } }

    // MARK: lifecycle

    func viewportChanged(_ pixels: PixelSize) {
        let first = viewport == nil
        viewport = pixels
        if first {
            connect()
            return
        }
        pendingResize?.cancel()
        pendingResize = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.connection?.send(.resize(pixels))
        }
    }

    func connect() {
        guard let viewport else { return }
        connection?.cancel()
        phase = .connecting
        checkedForDuplicate = false
        let video = self.video
        var h = ViewportConnection.Handlers()
        h.state = { [weak self] s in Task { @MainActor in self?.stateChanged(s) } }
        h.welcome = { [weak self] w in Task { @MainActor in self?.welcomed(w) } }
        h.displays = { [weak self] d in Task { @MainActor in self?.displays = d } }
        h.stream = { [weak self] s in Task { @MainActor in self?.streamChanged(s) } }
        h.video = { frame in video.enqueue(frame) }
        h.cursor = { [weak self] c in Task { @MainActor in self?.cursorPacket(c) } }
        h.thumbnail = { [weak self] t in Task { @MainActor in self?.thumbnails[t.displayID] = UIImage(data: t.jpeg) } }
        h.rtt = { [weak self] ms in Task { @MainActor in self?.rtt = ms } }
        let hello = Hello(
            clientName: UIDevice.current.name, viewport: viewport, preferredDisplayID: preferredDisplayID, focused: focused)
        let connection = ViewportConnection(link: link, hello: hello, handlers: h)
        video.onNeedKeyframe = { [weak connection] in connection?.requestKeyframe() }
        self.connection = connection
        connection.start()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        stopThumbnails()
        phase = .waiting
    }

    /// The window came back to the foreground: reconnect if iPadOS dropped the socket meanwhile.
    func sceneActive(_ active: Bool) {
        if active, case .failed = phase { connect() }
        setFocused(active)
    }

    func setFocused(_ value: Bool) {
        guard value != focused else { return }
        focused = value
        connection?.send(.focus(value))
        if !value { connection?.send(.input(.releaseAll)) }
    }

    // MARK: switching (T1-VP-03 / T2-NAT-04)

    func show(_ displayID: UInt32) {
        connection?.send(.subscribe(displayID: displayID))
        pickerOpen = false
        revealHUD()
    }

    func perform(_ action: SwitchAction) {
        if action == .picker {
            pickerOpen.toggle()
            return
        }
        if let target = SwitchShortcuts.target(action, current: currentDisplayID, displays: displays) { show(target) }
    }

    func revealHUD() {
        hudVisible = true
        hideHUD?.cancel()
        guard !pickerOpen else { return }
        hideHUD = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.hudVisible = false
        }
    }

    // MARK: input (T2-NAT-05)

    func send(_ event: InputEvent) {
        connection?.send(event)
    }

    func key(usage: UInt16, down: Bool) {
        if let action = shortcuts.handle(usage: usage, down: down) {
            swallowed.insert(usage)
            perform(action)
            return
        }
        if !down, swallowed.remove(usage) != nil { return }
        connection?.send(.key(usage: usage, down: down))
    }

    // MARK: host traffic

    private func stateChanged(_ state: ViewportConnection.State) {
        switch state {
        case .connecting: phase = .connecting
        case .connected: phase = .connected
        case .closed(let reason):
            phase = .failed(reason ?? "Disconnected")
            connection = nil
        }
    }

    private func welcomed(_ w: Welcome) {
        hostName = w.hostName
        displays = w.displays
    }

    private func streamChanged(_ s: StreamInfo) {
        contentSize = CGSize(width: s.contentSize.width, height: s.contentSize.height)
        fps = s.fps
        let changed = currentDisplayID != s.displayID
        currentDisplayID = s.displayID
        if let d = currentDisplay { displayLabelChanged?("\(d.index) · \(d.name)") }
        if changed {
            onDisplay(s.displayID)
            revealHUD()
        }
        // A new window that landed on a display another window already shows moves to the next free one.
        if !checkedForDuplicate {
            checkedForDuplicate = true
            let taken = avoidDisplays()
            if preferredDisplayID == nil, taken.contains(s.displayID),
               let free = displays.sorted(by: { $0.index < $1.index }).first(where: { !taken.contains($0.id) })
            {
                show(free.id)
            }
        }
    }

    private func cursorPacket(_ packet: CursorPacket) {
        switch packet {
        case .shape(let s):
            guard let image = UIImage(data: s.png) else { return }
            cursorChanged?(.shape(image, hotspot: CGPoint(x: s.hotspotX, y: s.hotspotY), size: CGSize(width: s.width, height: s.height)))
        case .hidden: cursorChanged?(.visible(false))
        case .visible: cursorChanged?(.visible(true))
        }
    }

    private func startThumbnails() {
        connection?.send(.requestThumbnails(maxWidth: 400))
        thumbnailTimer?.invalidate()
        thumbnailTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.connection?.send(.requestThumbnails(maxWidth: 400)) }
        }
    }

    private func stopThumbnails() {
        thumbnailTimer?.invalidate()
        thumbnailTimer = nil
    }
}

/// Hands decoded-ready H.264 frames to the window's display layer from the network queue.
final class VideoOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var renderer: AVSampleBufferVideoRenderer?
    private var needKeyframe: (@Sendable () -> Void)?

    var onNeedKeyframe: (@Sendable () -> Void)? {
        get { lock.withLock { needKeyframe } }
        set { lock.withLock { needKeyframe = newValue } }
    }

    func attach(_ layer: AVSampleBufferDisplayLayer) {
        let r = layer.sampleBufferRenderer
        lock.withLock { renderer = r }
    }

    func enqueue(_ frame: VideoFrame) {
        guard let renderer = lock.withLock({ renderer }) else { return }
        if frame.formatChanged { renderer.flush() }
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
            if !frame.isKeyframe {
                onNeedKeyframe?()
                return
            }
        }
        renderer.enqueue(frame.sample)
    }
}
