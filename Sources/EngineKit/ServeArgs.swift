import FrameKit

/// CLI for `mrdpd-serve` (T1-SEC-04). Strips SwiftPM's `--` so `just serve` binds the host, not the dash.
/// `--display A|B|C|main` (or `--display=B`) picks the Mac display; default is the main display (T1-MON-02).
public enum ServeArgs {
    public enum Error: Swift.Error, Equatable {
        case usage
        case unspecifiedBind(String)
    }

    public static func parse(_ arguments: [String]) throws -> (host: String, port: UInt16, display: DisplayChoice) {
        var args = Array(arguments.dropFirst())
        if args.first == "--" {
            args.removeFirst()
        }
        let display = try takeDisplay(&args)
        let host = args.first ?? "127.0.0.1"
        let portS = args.count > 1 ? args[1] : "3390"
        guard let port = UInt16(portS), port != 0 else {
            throw Error.usage
        }
        guard BindHost.isSpecified(host) else {
            throw Error.unspecifiedBind(host)
        }
        return (host, port, display)
    }

    private static func takeDisplay(_ args: inout [String]) throws -> DisplayChoice {
        let value: String
        if let i = args.firstIndex(of: "--display") {
            guard i + 1 < args.count else {
                throw Error.usage
            }
            value = args[i + 1]
            args.removeSubrange(i...(i + 1))
        } else if let i = args.firstIndex(where: { $0.hasPrefix("--display=") }) {
            value = String(args[i].dropFirst("--display=".count))
            args.remove(at: i)
        } else {
            return .main
        }
        if value.lowercased() == "main" {
            return .main
        }
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw Error.usage
        }
        return .letter(value.uppercased())
    }
}
