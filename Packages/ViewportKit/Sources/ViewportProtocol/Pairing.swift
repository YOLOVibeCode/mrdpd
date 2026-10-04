import Foundation

/// T2-NAT-02: everything a client needs to reach and authenticate to a host, as one link the
/// owner pastes on the iPad (Universal Clipboard) or scans as a QR code.
///
/// `key` is 32 random bytes generated on the Mac for this one device. It is the TLS pre-shared
/// key, so the link itself is a secret: show it once, never log it.
public struct PairingLink: Equatable, Sendable {
    public static let scheme = "mrdpd"
    public static let keyLength = 32

    public var hostName: String
    public var hostID: String
    public var address: String
    public var port: UInt16
    public var deviceID: String
    public var key: Data

    public init(hostName: String, hostID: String, address: String, port: UInt16, deviceID: String, key: Data) {
        self.hostName = hostName
        self.hostID = hostID
        self.address = address
        self.port = port
        self.deviceID = deviceID
        self.key = key
    }

    public var url: String {
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "name", value: hostName),
            URLQueryItem(name: "hid", value: hostID),
            URLQueryItem(name: "addr", value: address),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "dev", value: deviceID),
            URLQueryItem(name: "key", value: Self.base64url(key)),
        ]
        return c.string!
    }

    public init?(url string: String) {
        guard let c = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == Self.scheme, c.host == "pair"
        else { return nil }
        var q: [String: String] = [:]
        for item in c.queryItems ?? [] { q[item.name] = item.value }
        guard q["v"] == "1",
              let name = q["name"], !name.isEmpty,
              let hid = q["hid"], !hid.isEmpty,
              let addr = q["addr"], !addr.isEmpty,
              let portString = q["port"], let port = UInt16(portString), port != 0,
              let dev = q["dev"], !dev.isEmpty,
              let keyString = q["key"], let key = Self.unbase64url(keyString), key.count == Self.keyLength
        else { return nil }
        self.init(hostName: name, hostID: hid, address: addr, port: port, deviceID: dev, key: key)
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func unbase64url(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}
