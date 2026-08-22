import XCTest
import CoreGraphics
import InputKit

/// T1-IN-03: RDP pixels → Quartz global points. Not an `InputSink` method (ISP).
final class DisplayMapTests: XCTestCase {
    func testRetina2xMapsPixelsToPoints() {
        let map = DisplayMap(
            originX: 0,
            originY: 0,
            pointWidth: 100,
            pointHeight: 50,
            pixelWidth: 200,
            pixelHeight: 100
        )
        let p = map.cgLocation(rdpX: 20, rdpY: 40)
        XCTAssertEqual(p.x, 10, accuracy: 0.01, "T1-IN-03: 2x x")
        XCTAssertEqual(p.y, 20, accuracy: 0.01, "T1-IN-03: 2x y")
    }

    func testOriginOffsetIsAdded() {
        let map = DisplayMap(
            originX: 100,
            originY: 200,
            pointWidth: 10,
            pointHeight: 10,
            pixelWidth: 10,
            pixelHeight: 10
        )
        let p = map.cgLocation(rdpX: 3, rdpY: 4)
        XCTAssertEqual(p.x, 103, accuracy: 0.01)
        XCTAssertEqual(p.y, 204, accuracy: 0.01)
    }

    func testClampsToPixelBounds() {
        let map = DisplayMap(
            originX: 0,
            originY: 0,
            pointWidth: 10,
            pointHeight: 10,
            pixelWidth: 10,
            pixelHeight: 10
        )
        let neg = map.cgLocation(rdpX: -5, rdpY: -5)
        XCTAssertEqual(neg.x, 0, accuracy: 0.01)
        XCTAssertEqual(neg.y, 0, accuracy: 0.01)
        let hi = map.cgLocation(rdpX: 99, rdpY: 99)
        XCTAssertEqual(hi.x, 9, accuracy: 0.01, "T1-IN-03: last pixel column")
        XCTAssertEqual(hi.y, 9, accuracy: 0.01)
    }
}
