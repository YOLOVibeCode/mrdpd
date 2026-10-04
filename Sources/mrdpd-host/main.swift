import AppKit
import ApplicationServices
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import HostKit
import ViewportProtocol

// Native viewport host for the mrdpd iPad app (ADR 0008).
//
//   mrdpd-host serve  --bind <ip> [--port 3399] [--no-inject] [--log-input]
//   mrdpd-host pair   --bind <ip> [--port 3399] [--name "iPad Pro"] [--advertise <ip>]
//                     [--link-file <path>] [--print-link]
//   mrdpd-host devices
//   mrdpd-host unpair <device-id>
//
// Bind an explicit address (Tailscale or LAN); never 0.0.0.0 (T1-SEC-04).

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ line: String) {
    let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withColonSeparatorInTime])
    FileHandle.standardError.write(Data("[\(stamp)] \(line)\n".utf8))
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("mrdpd-host: \(message)\n".utf8))
    exit(code)
}

struct Options {
    var command = ""
    var positional: [String] = []
    var bind: String?
    var port: UInt16 = 3399
    var name = "iPad"
    var advertise: String?
    var linkFile: String?
    var printLink = false
    var inject = true
    var logInput = false

    init(_ args: [String]) {
        var it = args.dropFirst().makeIterator()
        command = it.next() ?? ""
        while let a = it.next() {
            switch a {
            case "--bind": bind = it.next()
            case "--port": port = UInt16(it.next() ?? "") ?? 0
            case "--name": name = it.next() ?? name
            case "--advertise": advertise = it.next()
            case "--link-file": linkFile = it.next()
            case "--print-link": printLink = true
            case "--no-inject": inject = false
            case "--log-input": logInput = true
            default: positional.append(a)
            }
        }
    }
}

let usage = """
    usage:
      mrdpd-host serve   --bind <ip> [--port 3399] [--no-inject] [--log-input]
      mrdpd-host pair    --bind <ip> [--port 3399] [--name NAME] [--advertise <ip>] [--link-file PATH] [--print-link]
      mrdpd-host devices
      mrdpd-host unpair  <device-id>
    """

let options = Options(CommandLine.arguments)
let store = PairingStore()
let hostName = Host.current().localizedName ?? "Mac"

func requireBind() -> String {
    guard let bind = options.bind, !bind.isEmpty else { fail("--bind <ip> is required (Tailscale or LAN address)\n\(usage)") }
    guard !["0.0.0.0", "::", "*"].contains(bind) else { fail("refuse unspecified bind \(bind) (T1-SEC-04)", code: 4) }
    guard options.port != 0 else { fail("--port must be 1…65535") }
    return bind
}

/// QR code as text: two modules per character row, black on white, with a quiet zone.
func terminalQR(_ text: String) -> String? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let image = filter.outputImage,
          let cg = CIContext().createCGImage(image, from: image.extent)
    else { return nil }
    let w = cg.width
    let h = cg.height
    var pixels = [UInt8](repeating: 255, count: w * h)
    guard let ctx = CGContext(
        data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let quiet = 2
    func dark(_ x: Int, _ y: Int) -> Bool {
        let mx = x - quiet
        let my = y - quiet
        guard mx >= 0, my >= 0, mx < w, my < h else { return false }
        return pixels[my * w + mx] < 128
    }
    var out = ""
    let size = w + quiet * 2
    for y in stride(from: 0, to: h + quiet * 2, by: 2) {
        out += "\u{1B}[30;47m"
        for x in 0..<size {
            switch (dark(x, y), dark(x, y + 1)) {
            case (true, true): out += "█"
            case (true, false): out += "▀"
            case (false, true): out += "▄"
            case (false, false): out += " "
            }
        }
        out += "\u{1B}[0m\n"
    }
    return out
}

switch options.command {
case "serve":
    let bind = requireBind()
    guard CGPreflightScreenCaptureAccess() else {
        fail("Screen Recording is not granted to this terminal; see docs/tcc.md")
    }
    if options.inject, !AXIsProcessTrusted() {
        log("Accessibility is not granted: the iPad can watch but not control (see docs/tcc.md)")
    }
    let engines = EncodePolicy.engineCount()
    let cursor = CursorMonitor()
    let poster: EventPosting = options.inject ? HIDEventPoster() : NullEventPoster()
    let observer: (@Sendable (String, InputEvent) -> Void)?
    if options.logInput {
        observer = { client, event in log("input \(client): \(event)") }
    } else {
        observer = nil
    }
    let env = HostEnvironment(
        hostName: hostName, hostID: (try? store.hostID()) ?? "unknown", displays: DisplayRegistry(),
        capture: SCKCaptureFactory(showsCursor: false), makeEncoder: { try H264Encoder(size: $0, fps: $1) },
        injector: NativeInputInjector(poster: poster), thumbnails: SCKThumbnailProvider(), cursor: cursor,
        scheduler: EncodeScheduler(engines: engines), log: log, inputObserver: observer)
    if !options.inject { log("--no-inject: input is received but not posted to this Mac") }
    cursor.start()
    let server = NativeServer(bindHost: bind, port: options.port, store: store, environment: env)
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    var signalSources: [DispatchSourceSignal] = []
    for sig in [SIGINT, SIGTERM] {
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            log("stopping")
            server.stop()
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
    Task {
        do {
            let port = try await server.start()
            let paired = (try? store.devices().count) ?? 0
            log("mrdpd-host listening \(bind):\(port) — \(paired) paired device(s), \(engines) hardware encoder(s)")
        } catch {
            fail("could not listen on \(bind):\(options.port): \(error)")
        }
    }
    dispatchMain()

case "pair":
    let bind = requireBind()
    do {
        let device = try store.pair(name: options.name)
        let link = PairingLink(
            hostName: hostName, hostID: try store.hostID(), address: options.advertise ?? bind, port: options.port,
            deviceID: device.id, key: device.key)
        if let path = options.linkFile {
            FileManager.default.createFile(atPath: path, contents: Data(link.url.utf8), attributes: [.posixPermissions: 0o600])
            print("Paired \"\(device.name)\" (\(device.id)). Link written to \(path) (secret: paste it on the iPad, then delete the file).")
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.url, forType: .string)
            if let qr = terminalQR(link.url) { print(qr) }
            print("Paired \"\(device.name)\" (\(device.id)) for \(link.address):\(link.port).")
            print("The pairing link is on this Mac's clipboard: in mrdpd on the iPad tap Paste (Universal Clipboard), or scan the code.")
            print("It is a secret key. Run `mrdpd-host unpair \(device.id)` if it leaks.")
            if options.printLink { print(link.url) }
        }
    } catch {
        fail("pairing failed: \(error)")
    }

case "devices":
    do {
        let all = try store.devices()
        if all.isEmpty { print("no paired devices") }
        for d in all { print("\(d.id)  \(d.name)  paired \(d.created.formatted(date: .abbreviated, time: .shortened))") }
    } catch {
        fail("could not read devices: \(error)")
    }

case "unpair":
    guard let id = options.positional.first else { fail(usage) }
    do {
        print(try store.remove(id: id) ? "unpaired \(id)" : "no device \(id)")
    } catch {
        fail("could not unpair: \(error)")
    }

default:
    print(usage)
    exit(options.command.isEmpty ? 0 : 1)
}
