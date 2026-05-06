import XCTest

/// Captures the three Build verification screen states (verified / failed /
/// development) for design review. Each state is forced via the
/// `COSIGN_BV_FIXTURE` launch-environment value the demo app reads in DEBUG.
final class BuildVerificationWalkthroughUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testBuildVerificationStates() {
        for state in ["verified", "failed", "development"] {
            launchDemo(fixture: state)
            waitForScreen("screen.build-verification")
            capture("build-verification-\(state)")
            app.terminate()
        }
    }

    private func launchDemo(fixture: String) {
        app = XCUIApplication()
        app.launchArguments = ["--cosign-demo=appstore", "--cosign-demo-reset", "--ui-testing"]
        app.launchEnvironment["COSIGN_BV_FIXTURE"] = fixture
        app.launch()
    }

    private func waitForScreen(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 30), "Missing screen \(identifier)")
    }

    private func capture(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
