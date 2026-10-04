import Foundation
import ViewportProtocol
import ViewportTransport

/// T2-NAT-02 host front end: accepts paired devices and runs one `ViewportSession` per window.
/// Re-reads the paired-device file every 2 s so `mrdpd-host pair` works while it runs.
public final class NativeServer: @unchecked Sendable {
    public let bindHost: String
    private let requestedPort: UInt16
    private let store: PairingStore
    private let env: HostEnvironment
    private let lock = NSLock()
    private var listener: FramedListener?
    private var port: UInt16 = 0
    private var sessions: [UUID: ViewportSession] = [:]
    private var devicesStamp: Date?
    private var watcher: DispatchSourceTimer?

    public init(bindHost: String, port: UInt16, store: PairingStore, environment: HostEnvironment) {
        self.bindHost = bindHost
        requestedPort = port
        self.store = store
        env = environment
    }

    public var sessionCount: Int { lock.withLock { sessions.count } }

    /// Starts listening; returns the bound port.
    public func start() async throws -> UInt16 {
        let bound = try await listen(port: requestedPort)
        lock.withLock { port = bound }
        devicesStamp = stamp()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "mrdpd.devices"))
        t.schedule(deadline: .now() + 2, repeating: 2)
        t.setEventHandler { [weak self] in self?.reloadIfDevicesChanged() }
        lock.withLock { watcher = t }
        t.resume()
        if let registry = env.displays as? DisplayRegistry {
            registry.observe { [weak self] in self?.displaysChanged() }
        }
        return bound
    }

    public func stop() {
        let (l, all) = lock.withLock { () -> (FramedListener?, [ViewportSession]) in
            watcher?.cancel()
            defer {
                listener = nil
                sessions = [:]
            }
            return (listener, Array(sessions.values))
        }
        l?.cancel()
        for s in all { s.connection.cancel() }
        env.injector.releaseAll()
    }

    private func listen(port: UInt16) async throws -> UInt16 {
        let keys = try store.keys()
        if keys.isEmpty { env.log("no paired devices yet: run `mrdpd-host pair`") }
        let log = env.log
        let listener = try FramedListener(host: bindHost, port: port, keys: keys) { identity in
            log("refused unknown device \"\(identity)\"")
        }
        let bound: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.start(
                ready: { result in once.run { continuation.resume(with: result) } },
                onConnection: { [weak self] connection in self?.accept(connection) })
        }
        lock.withLock { self.listener = listener }
        return bound
    }

    /// New key set: stop accepting with the old keys, then listen again on the same port.
    /// Open sessions are unaffected. The port can take a moment to free up, so retry briefly.
    private func relisten(port: UInt16) async throws {
        let old = lock.withLock { () -> FramedListener? in
            defer { listener = nil }
            return listener
        }
        old?.cancel()
        var lastError: Error?
        for _ in 0..<20 {
            do {
                _ = try await listen(port: port)
                return
            } catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw lastError ?? CancellationError()
    }

    private func accept(_ connection: FramedConnection) {
        let session = ViewportSession(connection: connection, env: env) { [weak self] id in
            _ = self?.lock.withLock { self?.sessions.removeValue(forKey: id) }
        }
        lock.withLock { sessions[session.id] = session }
        session.start()
    }

    private func stamp() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: store.devicesFile.path))?[.modificationDate] as? Date
    }

    private func reloadIfDevicesChanged() {
        let now = stamp()
        guard now != devicesStamp else { return }
        devicesStamp = now
        let port = lock.withLock { self.port }
        Task {
            do {
                try await relisten(port: port)
                env.log("paired devices changed: now \((try? store.keys().count) ?? 0)")
            } catch {
                env.log("could not reload paired devices: \(error)")
            }
        }
    }

    private func displaysChanged() {
        let all = lock.withLock { Array(sessions.values) }
        for s in all { Task { await s.displaysChanged() } }
    }
}

/// Runs a closure at most once (listener state can report ready and failed).
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        let first = lock.withLock { () -> Bool in
            defer { done = true }
            return !done
        }
        if first { body() }
    }
}
