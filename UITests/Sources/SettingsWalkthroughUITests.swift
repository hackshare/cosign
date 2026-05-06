import XCTest

/// Captures the Settings hub and the screens it links to (Network relay
/// connection, About, and the self-hosted relay advanced screen) for design
/// review. The demo build reports a healthy `NetworkHealth`, so the Network
/// screen renders its connected state.
final class SettingsWalkthroughUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSettingsHubWalkthrough() {
        launchDemo(profile: "appstore")
        waitForScreen("screen.signers")

        tapButton("Settings")
        waitForScreen("screen.settings")
        capture("settings-hub")

        tapButton("settings-network-row")
        waitForScreen("screen.network-settings")
        capture("network-relay")

        tapButton("network-self-hosted-row")
        waitForScreen("screen.self-hosted-relay")
        capture("self-hosted-relay")

        navigateBack()
        waitForScreen("screen.network-settings")
        navigateBack()
        waitForScreen("screen.settings")

        tapButton("settings-about-row")
        waitForScreen("screen.about")
        capture("about-cosign")
    }

    private func launchDemo(profile: String) {
        app.launchArguments = ["--cosign-demo=\(profile)", "--cosign-demo-reset", "--ui-testing"]
        app.launch()
    }

    private func tapButton(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "Missing button \(identifier)")
        button.tap()
    }

    private func waitForScreen(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 30), "Missing screen \(identifier)")
    }

    private func navigateBack() {
        let customBackButton = app.buttons["nav-back"]
        if customBackButton.waitForExistence(timeout: 2) {
            customBackButton.tap()
            return
        }

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 4), "Missing navigation back button")
        backButton.tap()
    }

    private func capture(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
