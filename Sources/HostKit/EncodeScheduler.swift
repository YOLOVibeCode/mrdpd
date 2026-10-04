import Foundation

/// T1-GFX-08: frame-rate budget across viewports (ADR 0007, spike R15). One "unit" is one
/// stream of ≤ `ViewportGeometry.maxPixelsAt60fps` at 60 fps, about one hardware encoder.
public enum EncodePolicy {
    /// Hardware H.264 encode engines by chip family. Max chips have two, Ultra four; base and Pro one.
    public static func engineCount(cpuBrand: String) -> Int {
        if cpuBrand.contains("Ultra") { return 4 }
        if cpuBrand.contains("Max") { return 2 }
        return 1
    }

    public static func engineCount() -> Int {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return engineCount(cpuBrand: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }

    /// `sessions` ordered most recently used first. Everyone gets 60 fps while the engines can
    /// carry it; otherwise the most recent gets 60 and the rest share what is left, never below 10.
    public static func allocate<ID: Hashable>(_ sessions: [ID], engines: Int) -> [ID: Int] {
        guard let first = sessions.first else { return [:] }
        guard sessions.count > engines else { return Dictionary(uniqueKeysWithValues: sessions.map { ($0, 60) }) }
        let others = sessions.count - 1
        let share = max(0, Double(engines) - 1) / Double(others)
        let fps = [60, 30, 20, 15, 10].first { Double($0) <= 60 * share } ?? 10
        var out: [ID: Int] = [first: 60]
        for id in sessions.dropFirst() { out[id] = fps }
        return out
    }
}

/// Tracks which viewports exist and which was used last; tells each its frame rate.
public final class EncodeScheduler: @unchecked Sendable {
    private let engines: Int
    private let lock = NSLock()
    private var recency: [UUID] = []
    private var listeners: [UUID: @Sendable (Int) -> Void] = [:]
    private var assigned: [UUID: Int] = [:]

    public init(engines: Int) {
        self.engines = max(1, engines)
    }

    public func register(_ id: UUID, onFPS: @escaping @Sendable (Int) -> Void) -> Int {
        let changes = lock.withLock { () -> [(UUID, Int)] in
            listeners[id] = onFPS
            recency.append(id)
            return recompute(except: id)
        }
        notify(changes)
        return lock.withLock { assigned[id] ?? 60 }
    }

    /// The user worked in this viewport (focus or input): it moves to the front.
    public func touch(_ id: UUID) {
        let changes = lock.withLock { () -> [(UUID, Int)] in
            guard recency.first != id, let i = recency.firstIndex(of: id) else { return [] }
            recency.remove(at: i)
            recency.insert(id, at: 0)
            return recompute(except: nil)
        }
        notify(changes)
    }

    public func unregister(_ id: UUID) {
        let changes = lock.withLock { () -> [(UUID, Int)] in
            listeners[id] = nil
            assigned[id] = nil
            recency.removeAll { $0 == id }
            return recompute(except: nil)
        }
        notify(changes)
    }

    public func fps(_ id: UUID) -> Int { lock.withLock { assigned[id] ?? 60 } }

    private func recompute(except skip: UUID?) -> [(UUID, Int)] {
        let next = EncodePolicy.allocate(recency, engines: engines)
        var changes: [(UUID, Int)] = []
        for (id, fps) in next where assigned[id] != fps {
            assigned[id] = fps
            if id != skip { changes.append((id, fps)) }
        }
        return changes
    }

    private func notify(_ changes: [(UUID, Int)]) {
        let calls = lock.withLock { changes.compactMap { change in listeners[change.0].map { ($0, change.1) } } }
        for (listener, fps) in calls { listener(fps) }
    }
}
