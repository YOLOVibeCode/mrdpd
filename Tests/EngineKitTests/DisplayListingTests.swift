import CoreGraphics
import XCTest
import EngineKit
import FrameKit

/// T1-MON-02: `mrdpd-serve` lists every Mac display at startup and warns when the served one has no menu bar.
final class DisplayListingTests: XCTestCase {
    private let catalog = DisplayCatalog(
        displays: [
            (displayID: 5, frame: CGRect(x: -2869, y: -2160, width: 3840, height: 2160)),
            (displayID: 1, frame: CGRect(x: 0, y: 0, width: 2056, height: 1329)),
            (displayID: 4, frame: CGRect(x: 971, y: -2160, width: 3840, height: 2160)),
        ],
        mainDisplayID: 1
    )
    private let names: [UInt32: String] = [1: "Built-in Retina Display", 4: "LG HDR 4K", 5: "LG HDR 4K"]

    func testListsEveryDisplayAndMarksMainAndServed() throws {
        let served = try XCTUnwrap(catalog.entry(for: .letter("C")))
        let lines = DisplayListing.lines(
            catalog: catalog, served: served, names: names, screensHaveSeparateSpaces: true
        )
        XCTAssertEqual(lines, [
            "Mac displays, left to right:",
            "  A  LG HDR 4K  3840x2160 at (-2869,-2160)",
            "  B  Built-in Retina Display  2056x1329 at (0,0)  main",
            "  C  LG HDR 4K  3840x2160 at (971,-2160)  serving",
        ], "T1-MON-02: startup listing")
    }

    func testServingMainIsMarkedOnce() throws {
        let served = try XCTUnwrap(catalog.entry(for: .main))
        let lines = DisplayListing.lines(
            catalog: catalog, served: served, names: names, screensHaveSeparateSpaces: false
        )
        XCTAssertEqual(lines[2], "  B  Built-in Retina Display  2056x1329 at (0,0)  main, serving", "T1-MON-02")
        XCTAssertFalse(lines.contains { $0.hasPrefix("warning:") }, "T1-MON-02: main has the menu bar")
    }

    func testWarnsWhenServedDisplayHasNoMenuBar() throws {
        let served = try XCTUnwrap(catalog.entry(for: .letter("A")))
        let lines = DisplayListing.lines(
            catalog: catalog, served: served, names: names, screensHaveSeparateSpaces: false
        )
        XCTAssertEqual(
            lines.last,
            "warning: display A has no menu bar or Dock because \"Displays have separate Spaces\" is off"
                + " (System Settings > Desktop & Dock)",
            "T1-MON-02: Spaces warning"
        )
    }

    func testNoWarningWithSeparateSpaces() throws {
        let served = try XCTUnwrap(catalog.entry(for: .letter("A")))
        let lines = DisplayListing.lines(
            catalog: catalog, served: served, names: names, screensHaveSeparateSpaces: true
        )
        XCTAssertFalse(lines.contains { $0.hasPrefix("warning:") }, "T1-MON-02: every display has a menu bar")
    }

    func testUnnamedDisplayFallsBackToID() throws {
        let served = try XCTUnwrap(catalog.entry(for: .main))
        let lines = DisplayListing.lines(
            catalog: catalog, served: served, names: [:], screensHaveSeparateSpaces: true
        )
        XCTAssertEqual(lines[1], "  A  Display 5  3840x2160 at (-2869,-2160)", "T1-MON-02: no NSScreen name")
    }
}
