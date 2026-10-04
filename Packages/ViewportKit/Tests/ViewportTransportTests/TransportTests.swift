import Foundation
import XCTest

import ViewportProtocol
@testable import ViewportTransport

/// T2-NAT-02: paired devices connect over TLS-PSK on loopback; unknown or wrong keys are refused.
final class TransportTests: XCTestCase {
    let key = Data((0..<32).map { UInt8($0 &* 7) })

    private func startServer(keys: [String: Data], onConnection: @escaping @Sendable (FramedConnection) -> Void) throws
        -> (FramedListener, UInt16)
    {
        let listener = try FramedListener(host: "127.0.0.1", port: 0, keys: keys)
        let ready = expectation(description: "listening")
        let box = PortBox()
        listener.start(
            ready: { result in
                box.port = (try? result.get()) ?? 0
                ready.fulfill()
            }, onConnection: onConnection)
        wait(for: [ready], timeout: 5)
        return (listener, box.port)
    }

    func testPairedDeviceExchangesFramesBothWays() throws {
        let serverGotHello = expectation(description: "server got hello")
        let clientGotWelcome = expectation(description: "client got welcome")
        let (listener, port) = try startServer(keys: ["device-A": key]) { conn in
            conn.start { event in
                if case .frame(let f) = event, case .hello = try? ControlCodec.clientMessage(f) {
                    serverGotHello.fulfill()
                    conn.send(HostMessage.welcome(Welcome(hostName: "Mac", hostID: "H", displays: [])))
                }
            }
        }
        defer { listener.cancel() }
        let client = FramedConnection(host: "127.0.0.1", port: port, deviceID: "device-A", key: key)
        client.start { event in
            switch event {
            case .ready:
                client.send(ClientMessage.hello(Hello(clientName: "test", viewport: PixelSize(width: 10, height: 10))))
            case .frame(let f):
                if case .welcome(let w) = try? ControlCodec.hostMessage(f), w.hostName == "Mac" { clientGotWelcome.fulfill() }
            case .closed:
                break
            }
        }
        wait(for: [serverGotHello, clientGotWelcome], timeout: 10)
        client.cancel()
    }

    func testLargeFrameSurvivesTheTrip() throws {
        let got = expectation(description: "big frame")
        let big = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0) })
        let (listener, port) = try startServer(keys: ["device-A": key]) { conn in
            conn.start { event in
                if case .ready = event { conn.send(WireFrame(kind: .video, payload: big)) }
            }
        }
        defer { listener.cancel() }
        let client = FramedConnection(host: "127.0.0.1", port: port, deviceID: "device-A", key: key)
        client.start { event in
            if case .frame(let f) = event, f.payload == big { got.fulfill() }
        }
        wait(for: [got], timeout: 10)
        client.cancel()
    }

    func testWrongKeyIsRefused() throws {
        let closed = expectation(description: "refused")
        let (listener, port) = try startServer(keys: ["device-A": key]) { conn in conn.start { _ in } }
        defer { listener.cancel() }
        let client = FramedConnection(host: "127.0.0.1", port: port, deviceID: "device-A", key: Data(repeating: 9, count: 32))
        client.start { event in
            switch event {
            case .ready: XCTFail("wrong key must not complete the handshake")
            case .closed(let reason): XCTAssertNotNil(reason); closed.fulfill()
            case .frame: XCTFail("no frames on a refused connection")
            }
        }
        wait(for: [closed], timeout: 10)
    }

    func testUnknownDeviceIsRefusedAndReported() throws {
        let closed = expectation(description: "refused")
        let reported = expectation(description: "reported")
        let listener = try FramedListener(host: "127.0.0.1", port: 0, keys: ["device-A": key]) { identity in
            if identity == "stranger" { reported.fulfill() }
        }
        let ready = expectation(description: "listening")
        let box = PortBox()
        listener.start(ready: { box.port = (try? $0.get()) ?? 0; ready.fulfill() }, onConnection: { $0.start { _ in } })
        wait(for: [ready], timeout: 5)
        defer { listener.cancel() }
        let client = FramedConnection(host: "127.0.0.1", port: box.port, deviceID: "stranger", key: key)
        client.start { event in
            if case .closed = event { closed.fulfill() }
            if case .ready = event { XCTFail("unknown device must not connect") }
        }
        wait(for: [closed, reported], timeout: 10)
    }

    func testUnspecifiedBindIsRefused() {
        XCTAssertThrowsError(try FramedListener(host: "0.0.0.0", port: 0, keys: [:])) { error in
            XCTAssertEqual(error as? FramedListener.ListenerError, .unspecifiedBind("0.0.0.0"))
        }
    }
}

final class PortBox: @unchecked Sendable {
    var port: UInt16 = 0
}
