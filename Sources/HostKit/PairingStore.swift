import Foundation
import Security
import ViewportProtocol

public struct PairedDevice: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// TLS pre-shared key. Secret.
    public var key: Data
    public var created: Date
}

/// T2-NAT-02: paired devices and the host's identity, under `MRDPD_HOME` or
/// `~/Library/Application Support/mrdpd` (directory 0700, files 0600).
///
/// Keys live in a 0600 file, not the Keychain, while the host is an unsigned dev binary: every
/// rebuild changes its code signature, and the login keychain would prompt on each access.
/// Moving to the Keychain is part of the signed host app (M12, T1-SEC-07).
public final class PairingStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let home = ProcessInfo.processInfo.environment["MRDPD_HOME"], !home.isEmpty {
            self.directory = URL(fileURLWithPath: home)
        } else {
            self.directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("mrdpd")
        }
    }

    public var devicesFile: URL { directory.appendingPathComponent("devices.json") }
    private var hostFile: URL { directory.appendingPathComponent("host.json") }

    public func hostID() throws -> String {
        try lock.withLock {
            if let data = try? Data(contentsOf: hostFile),
               let id = try? JSONDecoder().decode([String: String].self, from: data)["id"]
            {
                return id
            }
            let id = UUID().uuidString
            try write(try JSONEncoder().encode(["id": id]), to: hostFile)
            return id
        }
    }

    public func devices() throws -> [PairedDevice] {
        try lock.withLock { try readDevices() }
    }

    public func keys() throws -> [String: Data] {
        Dictionary(uniqueKeysWithValues: try devices().map { ($0.id, $0.key) })
    }

    /// A new device with a fresh random key. The caller shows the pairing link once.
    public func pair(name: String) throws -> PairedDevice {
        try lock.withLock {
            var key = Data(count: PairingLink.keyLength)
            let status = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, PairingLink.keyLength, $0.baseAddress!) }
            guard status == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
            let device = PairedDevice(
                id: String(UUID().uuidString.prefix(8)).lowercased(), name: name, key: key, created: Date())
            var all = try readDevices()
            all.append(device)
            try writeDevices(all)
            return device
        }
    }

    @discardableResult
    public func remove(id: String) throws -> Bool {
        try lock.withLock {
            var all = try readDevices()
            let before = all.count
            all.removeAll { $0.id == id }
            guard all.count != before else { return false }
            try writeDevices(all)
            return true
        }
    }

    private func readDevices() throws -> [PairedDevice] {
        guard let data = try? Data(contentsOf: devicesFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PairedDevice].self, from: data)
    }

    private func writeDevices(_ devices: [PairedDevice]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(try encoder.encode(devices), to: devicesFile)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let tmp = url.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600])
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
