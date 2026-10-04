import XCTest
import EngineKit
import FrameKit

/// T1-SEC-04: `swift run mrdpd-serve -- host port` must not treat `--` as the bind host.
/// T1-MON-02: `--display A|B|C|main` picks the Mac display; default is the main display.
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

    func testDisplayDefaultsToMain() throws {
        let parsed = try ServeArgs.parse(["mrdpd-serve"])
        XCTAssertEqual(parsed.display, .main, "T1-MON-02: default display")
    }

    func testDisplayFlagAfterPositionals() throws {
        let parsed = try ServeArgs.parse(["mrdpd-serve", "--", "100.64.0.1", "3391", "--display", "c"])
        XCTAssertEqual(parsed.host, "100.64.0.1")
        XCTAssertEqual(parsed.port, 3391)
        XCTAssertEqual(parsed.display, .letter("C"), "T1-MON-02: --display letter")
    }

    func testDisplayFlagBeforePositionals() throws {
        let parsed = try ServeArgs.parse(["mrdpd-serve", "--display=B", "127.0.0.1"])
        XCTAssertEqual(parsed.host, "127.0.0.1")
        XCTAssertEqual(parsed.port, 3390)
        XCTAssertEqual(parsed.display, .letter("B"), "T1-MON-02: --display=letter")
    }

    func testDisplayMainKeyword() throws {
        let parsed = try ServeArgs.parse(["mrdpd-serve", "--display", "main"])
        XCTAssertEqual(parsed.display, .main, "T1-MON-02: --display main")
    }

    func testDisplayWithoutValueIsUsage() {
        XCTAssertThrowsError(try ServeArgs.parse(["mrdpd-serve", "--display"])) { error in
            XCTAssertEqual(error as? ServeArgs.Error, .usage, "T1-MON-02: missing letter")
        }
    }

    func testDisplayRejectsNonLetters() {
        XCTAssertThrowsError(try ServeArgs.parse(["mrdpd-serve", "--display", "2"])) { error in
            XCTAssertEqual(error as? ServeArgs.Error, .usage, "T1-MON-02: letters only")
        }
    }
}
