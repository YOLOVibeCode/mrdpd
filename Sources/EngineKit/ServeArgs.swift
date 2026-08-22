/// CLI for `mrdpd-serve` (T1-SEC-04). Strips SwiftPM's `--` so `just serve` binds the host, not the dash.
public enum ServeArgs {
    public enum Error: Swift.Error, Equatable {
        case usage
        case unspecifiedBind(String)
    }

    public static func parse(_ arguments: [String]) throws -> (host: String, port: UInt16) {
        var args = Array(arguments.dropFirst())
        if args.first == "--" {
            args.removeFirst()
        }
        let host = args.first ?? "127.0.0.1"
        let portS = args.count > 1 ? args[1] : "3390"
        guard let port = UInt16(portS), port != 0 else {
            throw Error.usage
        }
        guard BindHost.isSpecified(host) else {
            throw Error.unspecifiedBind(host)
        }
        return (host, port)
    }
}
