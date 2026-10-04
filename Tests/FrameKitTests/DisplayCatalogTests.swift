import CoreGraphics
import XCTest
import FrameKit

/// T1-MON-02: Mac displays are lettered left to right, then top to bottom; the default is the main display.
final class DisplayCatalogTests: XCTestCase {
    private let left = (displayID: UInt32(5), frame: CGRect(x: -2869, y: -2160, width: 3840, height: 2160))
    private let laptop = (displayID: UInt32(1), frame: CGRect(x: 0, y: 0, width: 2056, height: 1329))
    private let right = (displayID: UInt32(4), frame: CGRect(x: 971, y: -2160, width: 3840, height: 2160))

    func testLettersDisplaysLeftToRight() {
        let catalog = DisplayCatalog(displays: [right, laptop, left], mainDisplayID: 1)
        XCTAssertEqual(catalog.entries.map(\.letter), ["A", "B", "C"], "T1-MON-02: letters")
        XCTAssertEqual(catalog.entries.map(\.displayID), [5, 1, 4], "T1-MON-02: left to right by minX")
    }

    func testSameLeftEdgeOrdersTopToBottom() {
        let lower = (displayID: UInt32(2), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let upper = (displayID: UInt32(3), frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        let catalog = DisplayCatalog(displays: [lower, upper], mainDisplayID: 2)
        XCTAssertEqual(catalog.entries.map(\.displayID), [3, 2], "T1-MON-02: top to bottom on ties")
    }

    func testDefaultIsMainDisplay() {
        let catalog = DisplayCatalog(displays: [right, laptop, left], mainDisplayID: 1)
        let served = catalog.entry(for: .main)
        XCTAssertEqual(served?.displayID, 1, "T1-MON-02: default is the main display")
        XCTAssertEqual(served?.letter, "B")
        XCTAssertEqual(catalog.entries.filter(\.isMain).map(\.displayID), [1], "T1-MON-02: one main")
    }

    func testLetterPicksDisplayIgnoringCase() {
        let catalog = DisplayCatalog(displays: [right, laptop, left], mainDisplayID: 1)
        XCTAssertEqual(catalog.entry(for: .letter("c"))?.displayID, 4, "T1-MON-02: letter lookup")
        XCTAssertEqual(catalog.entry(for: .letter("A"))?.frame, left.frame, "T1-MON-02: frame kept")
    }

    func testUnknownLetterIsNil() {
        let catalog = DisplayCatalog(displays: [right, laptop, left], mainDisplayID: 1)
        XCTAssertNil(catalog.entry(for: .letter("D")), "T1-MON-02: no fourth display")
    }

    func testMissingMainFallsBackToFirstLetter() {
        let catalog = DisplayCatalog(displays: [right, left], mainDisplayID: 1)
        XCTAssertEqual(catalog.entry(for: .main)?.letter, "A", "T1-MON-02: main not in the list")
    }

    func testLettersContinuePastZ() {
        let many = (0..<28).map { i in
            (displayID: UInt32(100 + i), frame: CGRect(x: Double(i) * 100, y: 0, width: 100, height: 100))
        }
        let catalog = DisplayCatalog(displays: many, mainDisplayID: 100)
        XCTAssertEqual(catalog.entries.suffix(2).map(\.letter), ["AA", "AB"], "T1-MON-02: letters past Z")
    }
}
