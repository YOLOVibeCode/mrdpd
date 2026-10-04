import CoreMedia
import Foundation
import ViewportProtocol
import ViewportTransport

/// T2-NAT-01/02 client session for one viewport window: connects as a paired device, says hello,
/// and turns host traffic into callbacks. Callbacks run on the connection's serial queue; UI code
/// hops to the main actor itself, video goes straight to the renderer.
public final class ViewportConnection: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case connecting
        case connected
        case closed(reason: String?)
    }

    public struct Handlers: Sendable {
        public var state: @Sendable (State) -> Void = { _ in }
        public var welcome: @Sendable (Welcome) -> Void = { _ in }
        public var displays: @Sendable ([DisplayInfo]) -> Void = { _ in }
        public var stream: @Sendable (StreamInfo) -> Void = { _ in }
        public var video: @Sendable (VideoFrame) -> Void = { _ in }
        public var cursor: @Sendable (CursorPacket) -> Void = { _ in }
        public var thumbnail: @Sendable (ThumbnailPacket) -> Void = { _ in }
        /// Round-trip time in milliseconds.
        public var rtt: @Sendable (Double) -> Void = { _ in }

        public init() {}
    }

    private let framed: FramedConnection
    private let hello: Hello
    private let handlers: Handlers
    private let lock = NSLock()
    private var builder = H264SampleBuilder()
    private var lastKeyframeRequest = Date.distantPast
    private var pings: [UInt32: Date] = [:]
    private var nextPing: UInt32 = 1
    private var pingTimer: DispatchSourceTimer?

    public init(host: String, port: UInt16, deviceID: String, key: Data, hello: Hello, handlers: Handlers) {
        framed = FramedConnection(host: host, port: port, deviceID: deviceID, key: key)
        self.hello = hello
        self.handlers = handlers
    }

    public convenience init(link: PairingLink, hello: Hello, handlers: Handlers) {
        self.init(host: link.address, port: link.port, deviceID: link.deviceID, key: link.key, hello: hello, handlers: handlers)
    }

    public func start() {
        handlers.state(.connecting)
        framed.start { [weak self] event in self?.handle(event) }
    }

    public func send(_ message: ClientMessage) {
        framed.send(message)
    }

    public func send(_ input: InputEvent) {
        framed.send(.input(input))
    }

    public func cancel() {
        lock.withLock {
            pingTimer?.cancel()
            pingTimer = nil
        }
        framed.send(.input(.releaseAll))
        framed.cancel()
    }

    private func handle(_ event: FramedConnection.Event) {
        switch event {
        case .ready:
            handlers.state(.connected)
            framed.send(.hello(hello))
            startPings()
        case .closed(let reason):
            lock.withLock {
                pingTimer?.cancel()
                pingTimer = nil
            }
            handlers.state(.closed(reason: reason))
        case .frame(let frame):
            route(frame)
        }
    }

    private func route(_ frame: WireFrame) {
        switch frame.kind {
        case .control:
            guard let message = try? ControlCodec.hostMessage(frame) else { return }
            switch message {
            case .welcome(let w): handlers.welcome(w)
            case .displays(let d): handlers.displays(d)
            case .stream(let s): handlers.stream(s)
            case .pong(let id):
                if let sent = lock.withLock({ pings.removeValue(forKey: id) }) {
                    handlers.rtt(Date().timeIntervalSince(sent) * 1000)
                }
            case .bye(let reason):
                handlers.state(.closed(reason: reason))
                framed.cancel()
            }
        case .video:
            guard let packet = try? VideoPacket(frame: frame) else { return }
            let output = lock.withLock { builder.make(packet) }
            switch output {
            case .frame(let f): handlers.video(f)
            case .needKeyframe: requestKeyframe()
            }
        case .cursor:
            if let c = try? CursorPacket(frame: frame) { handlers.cursor(c) }
        case .thumbnail:
            if let t = try? ThumbnailPacket(frame: frame) { handlers.thumbnail(t) }
        }
    }

    /// Ask for a keyframe at most twice a second (a decoder error or a missed epoch start).
    public func requestKeyframe() {
        let due = lock.withLock { () -> Bool in
            guard Date().timeIntervalSince(lastKeyframeRequest) > 0.5 else { return false }
            lastKeyframeRequest = Date()
            return true
        }
        if due { framed.send(.requestKeyframe) }
    }

    private func startPings() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "mrdpd.ping"))
        timer.schedule(deadline: .now() + 1, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let id = self.lock.withLock { () -> UInt32 in
                let id = self.nextPing
                self.nextPing &+= 1
                self.pings[id] = Date()
                if self.pings.count > 8 { self.pings.removeValue(forKey: self.pings.keys.min()!) }
                return id
            }
            self.framed.send(.ping(id: id))
        }
        lock.withLock { pingTimer = timer }
        timer.resume()
    }
}
