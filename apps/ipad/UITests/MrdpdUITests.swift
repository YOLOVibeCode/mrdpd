import XCTest

/// T2-NAT-03/04/05 in the simulator against a real `mrdpd-host --no-inject --log-input`
/// (nothing is posted to the Mac). Run through `just ipad-sim-check`, which starts the host,
/// pairs, passes the link in the environment, runs this, then checks the host's input log.
final class MrdpdUITests: XCTestCase {
    @MainActor
    func testConnectsSwitchesDisplaysAndSendsInput() throws {
        let link = try XCTUnwrap(
            ProcessInfo.processInfo.environment["MRDPD_UI_TEST_LINK"], "run through `just ipad-sim-check`")
        let app = XCUIApplication()
        app.launchEnvironment["MRDPD_UI_TEST_LINK"] = link
        app.launch()

        let remote = app.otherElements["remoteView"]
        XCTAssertTrue(remote.waitForExistence(timeout: 20), "the Mac display view appears")
        waitForValue(of: remote, matching: "value CONTAINS '·'", "connected and streaming a display")

        // Tap → click; a letter; Cmd+A (Mac semantics).
        remote.tap()
        remote.typeKey("a", modifierFlags: [])
        remote.typeKey("a", modifierFlags: [.command])

        // Ctrl+Option+N switches displays locally and is never sent to the Mac.
        remote.typeKey("1", modifierFlags: [.control, .option])
        waitForValue(of: remote, matching: "value BEGINSWITH '1 ·'", "Ctrl+Option+1 shows display 1")
        remote.typeKey("2", modifierFlags: [.control, .option])
        waitForValue(of: remote, matching: "value BEGINSWITH '2 ·'", "Ctrl+Option+2 shows display 2")

        // One-finger drag → left drag; long press → right click.
        let start = remote.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: remote.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        remote.press(forDuration: 1.2)
    }

    @MainActor
    private func waitForValue(of element: XCUIElement, matching format: String, _ what: String) {
        let found = expectation(for: NSPredicate(format: format), evaluatedWith: element)
        found.expectationDescription = what
        wait(for: [found], timeout: 20)
    }
}
