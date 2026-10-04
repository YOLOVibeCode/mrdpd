import Foundation
import Security
import ViewportProtocol

/// A Mac this iPad is paired with. The key itself lives in the Keychain, never in defaults.
struct PairedHost: Codable, Identifiable, Hashable, Sendable {
    var hostName: String
    var hostID: String
    var address: String
    var port: UInt16
    var deviceID: String

    var id: String { deviceID }
}

@MainActor
final class HostStore: ObservableObject {
    @Published private(set) var hosts: [PairedHost] = []
    private let defaultsKey = "pairedHosts"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([PairedHost].self, from: data)
        {
            hosts = saved.filter { Keychain.read(account: $0.deviceID) != nil }
        }
    }

    /// Adds (or replaces, for the same Mac) a host from a pairing link.
    @discardableResult
    func add(_ link: PairingLink) throws -> PairedHost {
        try Keychain.save(link.key, account: link.deviceID)
        let host = PairedHost(
            hostName: link.hostName, hostID: link.hostID, address: link.address, port: link.port, deviceID: link.deviceID)
        for old in hosts where old.hostID == link.hostID && old.deviceID != link.deviceID {
            Keychain.delete(account: old.deviceID)
        }
        hosts.removeAll { $0.hostID == link.hostID }
        hosts.append(host)
        persist()
        return host
    }

    func remove(_ host: PairedHost) {
        Keychain.delete(account: host.deviceID)
        hosts.removeAll { $0.deviceID == host.deviceID }
        persist()
    }

    func link(for host: PairedHost) -> PairingLink? {
        guard let key = Keychain.read(account: host.deviceID) else { return nil }
        return PairingLink(
            hostName: host.hostName, hostID: host.hostID, address: host.address, port: host.port, deviceID: host.deviceID,
            key: key)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }
}

enum Keychain {
    static let service = "com.noctusoft.mrdpd.pairing"

    struct Failure: Error { let status: OSStatus }

    static func save(_ data: Data, account: String) throws {
        delete(account: account)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func read(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(account: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
    }
}
