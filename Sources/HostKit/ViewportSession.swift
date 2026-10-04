import CoreGraphics
import Foundation
import ViewportProtocol
import ViewportTransport

/// What a session needs from the host. Real implementations in `mrdpd-host`; doubles in tests.
public struct HostEnvironment: Sendable {
    public var hostName: String
    public var hostID: String
    public var displays: DisplayListing
    public var capture: CaptureFactory
    public var makeEncoder: @Sendable (PixelSize, Int) throws -> H264Encoder
    public var injector: NativeInputInjector
    public var thumbnails: ThumbnailProviding
    public var cursor: CursorMonitor?
    public var scheduler: EncodeScheduler
    public var log: @Sendable (String) -> Void
    /// Sees every input event before injection (`mrdpd-host --log-input`; tests).
    public var inputObserver: (@Sendable (String, ViewportProtocol.InputEvent) -> Void)?

    public init(
        hostName: String, hostID: String, displays: DisplayListing, capture: CaptureFactory,
        makeEncoder: @escaping @Sendable (PixelSize, Int) throws -> H264Encoder, injector: NativeInputInjector,
        thumbnails: ThumbnailProviding, cursor: CursorMonitor?, scheduler: EncodeScheduler,
        log: @escaping @Sendable (String) -> Void,
        inputObserver: (@Sendable (String, ViewportProtocol.InputEvent) -> Void)? = nil
    ) {
        self.hostName = hostName
        self.hostID = hostID
        self.displays = displays
        self.capture = capture
        self.makeEncoder = makeEncoder
        self.injector = injector
        self.thumbnails = thumbnails
        self.cursor = cursor
        self.scheduler = scheduler
        self.log = log
        self.inputObserver = inputObserver
    }
}

/// One viewport (ADR 0006): one client window, one source display, switchable (T1-VP-03),
/// sized by the client (T1-VP-02). Control messages are handled strictly in order.
actor ViewportSession {
    nonisolated let id = UUID()
    nonisolated let connection: FramedConnection
    private let env: HostEnvironment
    private let pipeline: VideoPipeline
    private let onClose: @Sendable (UUID) -> Void
    private var clientName = "client"
    private var viewport = PixelSize(width: 1920, height: 1080)
    private var display: DisplayInfo?
    private var epoch: UInt32 = 0
    private var fps = 60
    private var size: PixelSize?
    private var capture: CaptureStream?
    private var cursorVisible: Bool?
    private var greeted = false
    private var closed = false

    init(connection: FramedConnection, env: HostEnvironment, onClose: @escaping @Sendable (UUID) -> Void) {
        self.connection = connection
        self.env = env
        self.onClose = onClose
        pipeline = VideoPipeline(connection: connection)
    }

    nonisolated func start() {
        let (events, inbox) = AsyncStream<FramedConnection.Event>.makeStream()
        connection.start { event in
            inbox.yield(event)
            if case .closed = event { inbox.finish() }
        }
        Task { await self.run(events) }
    }

    private func run(_ events: AsyncStream<FramedConnection.Event>) async {
        for await event in events {
            switch event {
            case .ready: break
            case .frame(let frame): await handle(frame)
            case .closed(let reason): await shutdown(reason: reason)
            }
        }
        await shutdown(reason: nil)
    }

    private func handle(_ frame: WireFrame) async {
        guard frame.kind == .control, let message = try? ControlCodec.clientMessage(frame) else { return }
        if !greeted {
            guard case .hello(let hello) = message else { return }
            await greet(hello)
            return
        }
        switch message {
        case .hello:
            break
        case .subscribe(let displayID):
            env.scheduler.touch(id)
            if let d = env.displays.displays().first(where: { $0.id == displayID }), d.id != display?.id {
                env.log("\(clientName): display \(d.index) \"\(d.name)\"")
                await show(d)
            }
        case .resize(let s):
            viewport = s
            await reconfigure(force: false)
        case .focus(let focused):
            if focused { env.scheduler.touch(id) }
        case .input(let event):
            env.inputObserver?(clientName, event)
            if let d = display { env.injector.inject(event, displayFrame: d.frame) }
            if case .releaseAll = event {} else { env.scheduler.touch(id) }
        case .requestKeyframe:
            pipeline.requestKeyframe()
        case .requestThumbnails(let maxWidth):
            let ids = env.displays.displays().map(\.id)
            let provider = env.thumbnails
            let connection = self.connection
            Task.detached {
                for packet in await provider.thumbnails(displayIDs: ids, maxWidth: min(max(maxWidth, 64), 640)) {
                    connection.send(packet.frame())
                }
            }
        case .ping(let pingID):
            connection.send(HostMessage.pong(id: pingID))
        }
    }

    private func greet(_ hello: Hello) async {
        guard hello.protocolVersion == ProtocolVersion.current else {
            connection.send(HostMessage.bye(reason: "protocol \(hello.protocolVersion) unsupported; host speaks \(ProtocolVersion.current)"))
            connection.cancel()
            return
        }
        greeted = true
        clientName = hello.clientName
        viewport = hello.viewport
        let list = env.displays.displays()
        connection.send(HostMessage.welcome(Welcome(hostName: env.hostName, hostID: env.hostID, displays: list)))
        fps = env.scheduler.register(id) { [weak self] fps in Task { await self?.setFPS(fps) } }
        if hello.focused { env.scheduler.touch(id) }
        let connection = self.connection
        env.cursor?.subscribe(
            id, shape: { connection.send(CursorPacket.shape($0).frame()) },
            location: { [weak self] p in Task { await self?.cursorMoved(p) } })
        env.log("\(clientName) connected from \(connection.remoteDescription), viewport \(viewport.width)x\(viewport.height)")
        let target = list.first { $0.id == hello.preferredDisplayID } ?? list.first { $0.isMain } ?? list.first
        if let target { await show(target) }
    }

    private func show(_ d: DisplayInfo) async {
        display = d
        await reconfigure(force: true)
        cursorVisible = nil
        if let cursor = env.cursor { cursorMoved(cursor.currentLocation) }
    }

    private func reconfigure(force: Bool) async {
        guard let d = display, !closed else { return }
        let newSize = ViewportGeometry.encodeSize(source: d.pixelSize, viewport: viewport)
        guard force || newSize != size else { return }
        size = newSize
        epoch &+= 1
        connection.send(HostMessage.stream(StreamInfo(displayID: d.id, epoch: epoch, contentSize: newSize, fps: fps)))
        do {
            pipeline.configure(encoder: try env.makeEncoder(newSize, fps), epoch: epoch, size: newSize)
        } catch {
            env.log("\(clientName): encoder failed: \(error)")
            pipeline.configure(encoder: nil, epoch: epoch, size: newSize)
        }
        if capture == nil {
            let pipeline = self.pipeline
            capture = env.capture.makeStream { pipeline.submit($0) }
        }
        do {
            try await capture?.apply(CaptureTarget(displayID: d.id, size: newSize, fps: fps))
            pipeline.accept()
        } catch {
            env.log("\(clientName): capture failed: \(error)")
            connection.send(HostMessage.bye(reason: "capture failed: \(error)"))
        }
    }

    private func setFPS(_ newFPS: Int) async {
        guard newFPS != fps, let d = display, let size, !closed else { return }
        fps = newFPS
        pipeline.setFrameRate(newFPS)
        try? await capture?.apply(CaptureTarget(displayID: d.id, size: size, fps: newFPS))
        connection.send(HostMessage.stream(StreamInfo(displayID: d.id, epoch: epoch, contentSize: size, fps: newFPS)))
    }

    private func cursorMoved(_ p: CGPoint) {
        guard let d = display, !closed else { return }
        let inside = p.x >= d.frame.x && p.x < d.frame.x + d.frame.width && p.y >= d.frame.y && p.y < d.frame.y + d.frame.height
        guard inside != cursorVisible else { return }
        cursorVisible = inside
        connection.send((inside ? CursorPacket.visible : .hidden).frame())
    }

    func displaysChanged() async {
        guard greeted, !closed else { return }
        let list = env.displays.displays()
        connection.send(HostMessage.displays(list))
        if let current = display, let updated = list.first(where: { $0.id == current.id }) {
            display = updated
            if updated.pixelSize != current.pixelSize { await reconfigure(force: true) }
        } else if let fallback = list.first(where: { $0.isMain }) ?? list.first {
            await show(fallback)
        }
    }

    private func shutdown(reason: String?) async {
        guard !closed else { return }
        closed = true
        env.injector.releaseAll()
        env.scheduler.unregister(id)
        env.cursor?.unsubscribe(id)
        await capture?.stop()
        capture = nil
        pipeline.stop()
        env.log("\(clientName) disconnected\(reason.map { ": \($0)" } ?? "")")
        onClose(id)
    }
}
