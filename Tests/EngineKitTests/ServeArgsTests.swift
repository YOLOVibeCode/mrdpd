import XCTest
import EngineKit

/// T1-SEC-04: `swift run mrdpd-serve -- host port` must not treat `--` as the bind host.
final class ServeArgsTests: XCTestCase {
    func testStripsSwiftRunDashDash() throws {
        let parsed = try ServeArgs.parse(["mrdpd-serve", "--", "127.0.0.1", "3390"])
        XCTAssertEqual(parsed.host, "127.0.0.1")
        XCTAssertEqual(parsed.port, 3390)
    }

    func testDefaultsLoopback3390() throws {
        let parsed = try ServeArgs.parse(["mrdpd-serve"])
        XCTAssertEqual(parsed.host, "127.0.0.1")
        XCTAssertEqual(parsed.port, 3390)
    }

    func testUnspecifiedBindThrows() {
        XCTAssertThrowsError(try ServeArgs.parse(["mrdpd-serve", "0.0.0.0", "3390"])) { error in
            guard case ServeArgs.Error.unspecifiedBind("0.0.0.0") = error else {
                return XCTFail("T1-SEC-04: \(error)")
            }
        }
    }

    func testStripsDashDashBeforeUnspecifiedBind() {
        XCTAssertThrowsError(try ServeArgs.parse(["mrdpd-serve", "--", "0.0.0.0", "3390"])) { error in
            guard case ServeArgs.Error.unspecifiedBind("0.0.0.0") = error else {
                return XCTFail("T1-SEC-04: \(error)")
            }
        }
    }
}
