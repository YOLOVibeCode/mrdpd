import Foundation
import Network
import ViewportProtocol

/// T2-NAT-02: TLS 1.2 ECDHE-PSK (ChaCha20-Poly1305) over TCP. Each paired device has its own
/// random 32-byte key (`PairingLink.key`), so there are no certificates, the session has forward
/// secrecy, and a wrong or unknown key fails the handshake ("bad MAC").
///
/// ADR 0008 named QUIC; v1 uses TCP + TLS-PSK because Network.framework supports it on both
/// platforms without certificate management. One connection per viewport window keeps a busy
/// 4K stream from blocking another window's input. QUIC can replace this behind the same API.
public enum ViewportTLS {
    /// `TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256`.
    static let cipherSuite: UInt16 = 0xCCAC

    public static func clientParameters(deviceID: String, key: Data) -> NWParameters {
        let tls = baseTLS()
        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions, dispatchData(key) as __DispatchData,
            dispatchData(Data(deviceID.utf8)) as __DispatchData)
        return parameters(tls)
    }

    /// `keys`: device ID → key, for every paired device.
    public static func serverParameters(keys: [String: Data], onUnknownDevice: (@Sendable (String) -> Void)? = nil)
        -> NWParameters
    {
        let tls = baseTLS()
        let sec = tls.securityProtocolOptions
        for (device, key) in keys {
            sec_protocol_options_add_pre_shared_key(
                sec, dispatchData(key) as __DispatchData, dispatchData(Data(device.utf8)) as __DispatchData)
        }
        let known = keys
        sec_protocol_options_set_pre_shared_key_selection_block(
            sec,
            { _, presented, complete in
                let identity = presented.map { String(decoding: Data($0 as DispatchData), as: UTF8.self) } ?? ""
                guard known[identity] != nil else {
                    onUnknownDevice?(identity)
                    complete(nil)
                    return
                }
                complete(dispatchData(Data(identity.utf8)) as __DispatchData)
            }, DispatchQueue(label: "mrdpd.tls.psk"))
        let params = parameters(tls)
        params.allowLocalEndpointReuse = true
        return params
    }

    private static func baseTLS() -> NWProtocolTLS.Options {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(sec, tls_ciphersuite_t(rawValue: cipherSuite)!)
        return tls
    }

    private static func parameters(_ tls: NWProtocolTLS.Options) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.connectionTimeout = 10
        return NWParameters(tls: tls, tcp: tcp)
    }

    static func dispatchData(_ d: Data) -> DispatchData {
        d.withUnsafeBytes { DispatchData(bytes: $0) }
    }
}

/// A framed, ordered, bidirectional message stream over one NWConnection.
public final class FramedConnection: @unchecked Sendable {
    public enum Event: Sendable {
        case ready
        case frame(WireFrame)
        /// Terminal. `reason` is nil for a clean close.
        case closed(reason: String?)
    }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var decoder = WireDecoder()
    private var pending = 0
    private var handler: (@Sendable (Event) -> Void)?
    private var finished = false

    public init(connection: NWConnection, queue: DispatchQueue = DispatchQueue(label: "mrdpd.framed")) {
        self.connection = connection
        self.queue = queue
    }

    /// Connects to `host:port` as a paired device.
    public convenience init(host: String, port: UInt16, deviceID: String, key: Data) {
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!,
            using: ViewportTLS.clientParameters(deviceID: deviceID, key: key))
        self.init(connection: connection)
    }

    public var remoteDescription: String { "\(connection.endpoint)" }

    /// Events arrive in order on one serial queue.
    public func start(_ handler: @escaping @Sendable (Event) -> Void) {
        lock.withLock { self.handler = handler }
        connection.stateUpdateHandler = { [weak self] state in self?.stateChanged(state) }
        connection.start(queue: queue)
    }

    /// Frames still waiting for the network stack. The host drops video at the source when this grows.
    public var pendingSends: Int { lock.withLock { pending } }

    public func send(_ frame: WireFrame, completion: (@Sendable (Bool) -> Void)? = nil) {
        lock.withLock { pending += 1 }
        connection.send(
            content: frame.encoded(),
            completion: .contentProcessed { [weak self] error in
                if let self { self.lock.withLock { self.pending -= 1 } }
                completion?(error == nil)
            })
    }

    public func send(_ message: ClientMessage) {
        guard let frame = try? ControlCodec.frame(message) else { return }
        send(frame)
    }

    public func send(_ message: HostMessage) {
        guard let frame = try? ControlCodec.frame(message) else { return }
        send(frame)
    }

    public func cancel() {
        connection.cancel()
    }

    private func stateChanged(_ state: NWConnection.State) {
        switch state {
        case .ready:
            emit(.ready)
            receive()
        case .failed(let error):
            finish(reason: "\(error)")
        case .waiting(let error):
            // Refused, unreachable, or TLS rejected: fail fast; the caller decides whether to retry.
            finish(reason: "\(error)")
            connection.cancel()
        case .cancelled:
            finish(reason: nil)
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let frames: [WireFrame]
                do {
                    frames = try self.lock.withLock { try self.decoder.append(data) }
                } catch {
                    self.finish(reason: "protocol error: \(error)")
                    self.connection.cancel()
                    return
                }
                for frame in frames { self.emit(.frame(frame)) }
            }
            if let error {
                self.finish(reason: "\(error)")
                self.connection.cancel()
                return
            }
            if isComplete {
                self.finish(reason: nil)
                self.connection.cancel()
                return
            }
            self.receive()
        }
    }

    private func emit(_ event: Event) {
        let h = lock.withLock { finished ? nil : handler }
        h?(event)
    }

    private func finish(reason: String?) {
        let h: (@Sendable (Event) -> Void)? = lock.withLock {
            guard !finished else { return nil }
            finished = true
            defer { handler = nil }
            return handler
        }
        h?(.closed(reason: reason))
    }
}

/// Accepts paired devices on an explicit address (never 0.0.0.0; T1-SEC-04).
public final class FramedListener: @unchecked Sendable {
    public enum ListenerError: Error, Equatable {
        case unspecifiedBind(String)
        case badPort
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "mrdpd.listener")

    public init(host: String, port: UInt16, keys: [String: Data], onUnknownDevice: (@Sendable (String) -> Void)? = nil)
        throws
    {
        guard !["0.0.0.0", "::", "*", ""].contains(host) else { throw ListenerError.unspecifiedBind(host) }
        let params = ViewportTLS.serverParameters(keys: keys, onUnknownDevice: onUnknownDevice)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw ListenerError.badPort }
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: nwPort)
        listener = try NWListener(using: params)
    }

    /// Calls `ready` with the bound port (useful when `port` was 0), then `onConnection` per client.
    public func start(
        ready: @escaping @Sendable (Result<UInt16, Error>) -> Void,
        onConnection: @escaping @Sendable (FramedConnection) -> Void
    ) {
        let listener = self.listener
        listener.newConnectionHandler = { connection in
            onConnection(FramedConnection(connection: connection, queue: DispatchQueue(label: "mrdpd.session")))
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready(.success(listener.port?.rawValue ?? 0))
            case .failed(let error): ready(.failure(error))
            default: break
            }
        }
        listener.start(queue: queue)
    }

    public func cancel() {
        listener.cancel()
    }
}
