import EngineKit
import FrameKit
import Foundation
import InputKit

/// Lab process: SCK → FramePump → real engine; CGEventInputSink (T1-IN-04).
@main
enum ServeMain {
    static func main() async {
        let host: String
        let port: UInt16
        do {
            let parsed = try ServeArgs.parse(CommandLine.arguments)
            host = parsed.host
            port = parsed.port
        } catch ServeArgs.Error.unspecifiedBind(let bad) {
            fputs("T1-SEC-04: refuse unspecified bind \(bad); pass 127.0.0.1 or an explicit iface\n", stderr)
            exit(4)
        } catch {
            fputs("usage: mrdpd-serve [host] [port]  (port 1...65535, not 0)\n", stderr)
            exit(1)
        }

        do {
            let dylib = try EngineDylib.path()
            let source = try await SCKFrameSource()
            let first = await source.nextFrame()
            guard first.width > 0, first.height > 0,
                  first.width <= UInt32(UInt16.max), first.height <= UInt32(UInt16.max)
            else {
                fputs("mrdpd-serve: desktop size not representable in ABI u16\n", stderr)
                exit(1)
            }
            let map = DisplayMap(
                pointFrame: source.pointFrame,
                pixelWidth: source.pixelWidth,
                pixelHeight: source.pixelHeight
            )
            let sink: any InputSink
            do {
                sink = try CGEventInputSink(map: map)
            } catch CGEventInputSinkError.denied {
                fputs("T1-OPS-03: Accessibility TCC missing; see docs/tcc.md\n", stderr)
                exit(1)
            }
            let engine = try Engine(dylibPath: dylib)
            try engine.start(
                config: EngineConfig(
                    bindHost: host,
                    bindPort: port,
                    desktopWidth: UInt16(first.width),
                    desktopHeight: UInt16(first.height)
                ),
                sink: sink
            )
            try engine.push(first)
            fputs(
                "mrdpd-serve listening \(host):\(port) \(first.width)x\(first.height) (NLA user mrdpd)\n",
                stderr
            )

            let pump = FramePump(source: source, engine: engine)
            while true {
                if try await pump.pumpOnce() {
                    continue
                }
                try await Task.sleep(for: .milliseconds(1))
            }
        } catch {
            fputs("mrdpd-serve: \(error)\n", stderr)
            exit(1)
        }
    }
}
