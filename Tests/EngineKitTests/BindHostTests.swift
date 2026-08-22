import XCTest
@testable import EngineKit

/// T1-SEC-04: Swift lab process refuses unspecified bind (same policy as `mrdpd-pattern`).
final class BindHostTests: XCTestCase {
    func testUnspecifiedAddressesAreRejected() {
        XCTAssertFalse(BindHost.isSpecified("0.0.0.0"), "T1-SEC-04")
        XCTAssertFalse(BindHost.isSpecified("::"), "T1-SEC-04")
        XCTAssertFalse(BindHost.isSpecified("*"), "T1-SEC-04")
    }

    func testLoopbackAndTailscaleAreAllowed() {
        XCTAssertTrue(BindHost.isSpecified("127.0.0.1"))
        XCTAssertTrue(BindHost.isSpecified("100.64.0.1"))
    }
}
