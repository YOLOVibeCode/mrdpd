import XCTest
import FrameKit

/// T1-GFX-05: cursor is composited in the captured frame (SCK `showsCursor`).
/// Not a `FrameSource` method (ISP).
final class SCKSettingsTests: XCTestCase {
    func testDefaultCompositesCursor() {
        XCTAssertTrue(SCKSettings().showsCursor, "T1-GFX-05: showsCursor default")
    }
}
