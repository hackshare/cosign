import XCTest

// MARK: - Base class

class DemoWalkthroughUITestCase: XCTestCase {
    fileprivate var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: Navigation helpers

    fileprivate func launchDemo(profile: String, extraArgs: [String] = []) {
        app.launchArguments = ["--cosign-demo=\(profile)", "--cosign-demo-reset", "--ui-testing"] + extraArgs
        app.launch()
    }

    fileprivate func openFirstVault() {
        waitForScreen("screen.signers")
        tapButton("signer-row-0")
        waitForScreen("screen.signer-home")
        tapButton("signer-home-squad-row-0")
        waitForScreen("screen.squad-detail")
        tapButton("vault-row-0")
        waitForScreen("screen.vault-detail")
    }

    fileprivate func openFirstSquadProposals() {
        waitForScreen("screen.signers")
        tapButton("signer-row-0")
        waitForScreen("screen.signer-home")
        tapButton("signer-home-squad-row-0")
        waitForScreen("screen.squad-detail")
        tapButton("tab-proposals")
        waitForButton("proposal-preview-row-0")
    }

    fileprivate func captureProposalDetail(row: Int, name: String) {
        tapButton("proposal-preview-row-\(row)")
        waitForScreen("screen.proposal-detail")
        capture(name)
        navigateBack()
        waitForScreen("screen.squad-detail")
        waitForButton("proposal-preview-row-0")
    }

    fileprivate func captureFirstVaultSurfaces() {
        tapButton("vault-row-0")
        waitForScreen("screen.vault-detail")
        capture("04-vault-tokens")
        tapButton("vault-action-inspect")
        waitForScreen("screen.vault-inspection")
        capture("05-vault-inspection")
        navigateBack()
        waitForScreen("screen.vault-detail")
        tapButton("tab-nfts")
        capture("06-vault-nfts")
        navigateBack()
        waitForScreen("screen.squad-detail")
    }

    /// Hardware add-signer screens trigger "no device" error sheets in the
    /// simulator that block in-place dismissal, so relaunch fresh per type.
    fileprivate func captureAddSignerFresh(option: String, screen: String, chooserName: String?, name: String) {
        launchDemo(profile: "appstore")
        waitForScreen("screen.signers")
        tapButton("signer-add-cta")
        waitForScreen("screen.add-signer-chooser")
        if let chooserName {
            capture(chooserName)
        }
        tapButton("signer-option-\(option)")
        waitForScreen(screen)
        capture(name)
    }

    // MARK: Interaction helpers

    fileprivate func tapButton(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 60), "Missing button \(identifier)")
        button.tap()
    }

    fileprivate func tapFirstButton(_ label: String) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 60), "Missing button \(label)")
        button.tap()
    }

    fileprivate func longPressButton(_ identifier: String, duration: TimeInterval) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 60), "Missing element \(identifier)")
        element.press(forDuration: duration)
    }

    /// Taps any element (not restricted to button type) matching the identifier.
    /// Useful for elements whose SwiftUI type doesn't map to UIKit's button trait.
    fileprivate func tapElement(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 60), "Missing element \(identifier)")
        element.tap()
    }

    fileprivate func typeText(_ identifier: String, _ text: String) {
        let textField = app.textFields[identifier]
        XCTAssertTrue(textField.waitForExistence(timeout: 60), "Missing text field \(identifier)")
        textField.tap()
        textField.typeText(text)
    }

    fileprivate func waitForElement(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 60), "Missing element \(identifier)")
    }

    fileprivate func waitForButton(_ identifier: String) {
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 60), "Missing button \(identifier)")
    }

    fileprivate func waitForText(_ label: String) {
        XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 60), "Missing text \(label)")
    }

    fileprivate func waitForScreen(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 60), "Missing screen \(identifier)")
    }

    fileprivate func dismissSheet() {
        let closeButton = app.buttons[CosignUITestCopy.close]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 4), "Missing sheet close button")
        closeButton.tap()
    }

    fileprivate func navigateBack() {
        let customBackButton = app.buttons["nav-back"]
        if customBackButton.waitForExistence(timeout: 2) {
            customBackButton.tap()
            return
        }

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 4), "Missing navigation back button")
        backButton.tap()
    }

    fileprivate func capture(_ name: String) {
        dismissKeyboardIfPresent(in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Core surfaces + confidence states

final class CoreSurfacesUITests: DemoWalkthroughUITestCase {
    func testDemoDesignWalkthroughLoadsCoreSurfaces() {
        launchDemo(profile: "appstore")
        waitForScreen("screen.signers")
        capture("01-signers")

        tapButton("signer-row-0")
        waitForScreen("screen.signer-home")
        waitForButton("signer-home-squad-row-0")
        capture("02-signer-home")

        tapButton("signer-home-squad-row-0")
        waitForScreen("screen.squad-detail")
        waitForButton("vault-row-0")
        capture("03-squad-vaults")

        captureFirstVaultSurfaces()

        tapButton("tab-proposals")
        waitForButton("proposal-preview-row-0")
        capture("07-squad-proposals")
        tapButton("proposal-preview-row-1")
        waitForScreen("screen.proposal-detail")
        capture("08-proposal-detail")
        // The predicted asset-movement card sits below the decoded fields.
        app.swipeUp()
        app.swipeUp()
        capture("61-predicted-movement")
        tapButton("proposal-sticky-action-more")
        waitForScreen("screen.proposal-secondary-actions")
        capture("09-proposal-more-actions")
        tapButton(CosignUITestCopy.cancel)
        waitForScreen("screen.proposal-detail")
        tapButton("proposal-sticky-action-approveAndExecute")
        waitForElement("proposal-signing-hold-button")
        capture("10-proposal-signing-sheet")
        longPressButton("proposal-signing-hold-button", duration: 1.8)
        waitForText("Approved & executed")
        capture("11-proposal-receipt")
        tapButton("receipt-inspect-execute")
        waitForScreen("screen.transaction-inspection")
        capture("12-transaction-inspection")
        navigateBack()
        waitForScreen("screen.proposal-detail")
        // The asset-movement card sits below the decoded fields; scroll it into view.
        app.swipeUp()
        app.swipeUp()
        capture("60-exec-movement")
        navigateBack()
        waitForScreen("screen.squad-detail")

        tapButton("tab-activity")
        capture("13-squad-activity")
        capture("62-activity-enriched")

        // The top activity row is a failed execution: open it to capture the
        // attempted asset-movement card and the FAILED execution status.
        tapButton("activity-row-0")
        waitForScreen("screen.transaction-inspection")
        capture("63-failed-inspection")
        app.swipeUp()
        capture("64-failed-status")
        navigateBack()
        waitForScreen("screen.squad-detail")

        tapButton("tab-members")
        capture("14-squad-members")

        // A member row opens that member's squads list, where each squad with
        // open proposals shows a pending pill.
        tapButton("member-row-0")
        waitForScreen("screen.squads-list")
        capture("55-squads-list")
        navigateBack()
        waitForScreen("screen.squad-detail")
        tapButton("tab-members")

        tapButton("squad-manage-cta")
        waitForScreen("screen.manage-squad")
        capture("50-manage-squad")

        // Permission: grant Propose to member index 2 (canInitiate is off in the
        // fixture), showing the mint-ring Changed chip and the "Changed" row badge.
        // Second tap resets it to its original off state.
        tapButton("manage-squad-perm-2-propose")
        capture("80-manage-perms-changed")
        tapButton("manage-squad-perm-2-propose")

        // Rent collector: scroll to the bottom section, stage the wrapped-SOL
        // address via the submit action (shows Changed / diff since the squad starts
        // without a collector), then clear to reset. The RunLoop wait lets the
        // keyboard dismiss animation finish so capture's dismissKeyboardIfPresent
        // is a no-op and doesn't interfere with the scroll position.
        app.swipeUp()
        app.swipeUp()
        typeText("manage-squad-rent-field", "So11111111111111111111111111111111111111112\n")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        waitForButton("manage-squad-rent-clear")
        capture("81-rent-collector-set")
        tapButton("manage-squad-rent-clear")
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()

        // Time lock: default (Currently: None), then a staged 24h change with
        // the mint chip and the "Time lock: None -> 24 hours" diff line.
        app.swipeUp()
        capture("70-timelock-default")
        tapButton("manage-squad-timelock-preset-24h")
        capture("71-timelock-staged")
        tapButton("manage-squad-timelock-preset-off")
        app.swipeDown()
        app.swipeDown()

        // Stage an addition: diff summary + pending member row. The trailing
        // newline submits the field, adding the member and dismissing the keyboard.
        typeText("manage-squad-new-member", "So11111111111111111111111111111111111111112\n")
        capture("51-manage-squad-staged-add")
        tapButton("manage-squad-remove-added-0")

        // Remove the current signer: threshold-aware self-removal warning.
        tapButton("manage-squad-remove-you")
        capture("52-manage-squad-self-removal")

        // Removing the other initiator leaves no proposer/executor: validation banner.
        tapButton("manage-squad-remove-1")
        waitForElement("manage-squad-validation-banner")
        capture("53-manage-squad-validation")
    }

    func testDemoConfidenceStates() {
        launchDemo(profile: "appstore")
        waitForScreen("screen.signers")
        tapButton("signer-row-1")
        waitForScreen("screen.signer-home")
        tapButton("signer-home-squad-row-0")
        waitForScreen("screen.squad-detail")
        tapButton("tab-proposals")
        waitForButton("proposal-preview-row-0")

        tapButton("proposal-preview-row-0")
        waitForScreen("screen.proposal-detail")
        capture("38-proposal-idl-confidence")
        navigateBack()
        waitForScreen("screen.squad-detail")
        waitForButton("proposal-preview-row-1")

        tapButton("proposal-preview-row-1")
        waitForScreen("screen.proposal-detail")
        capture("39-proposal-partial-confidence")
    }
}

// MARK: - Proposal builder + status flows

final class ProposalFlowUITests: DemoWalkthroughUITestCase {
    func testDemoProposalBuilderSelectorsLoadDesignSurfaces() {
        launchDemo(profile: "appstore")
        openFirstVault()

        tapFirstButton("Propose")
        waitForScreen("screen.create-transfer-proposal")
        capture("14-create-transfer")

        tapButton("selector-field-vault")
        waitForScreen("screen.selector-sheet")
        capture("15-selector-vault")
        dismissSheet()

        tapButton("selector-field-asset")
        waitForScreen("screen.selector-sheet")
        capture("16-selector-asset")
        dismissSheet()

        tapButton("proposal-builder-next")
        capture("17-create-transfer-recipient")
        typeText("proposal-builder-recipient", CosignUITestCopy.demoRecipient)
        tapButton("proposal-builder-next")
        capture("18-create-transfer-amount")
        typeText("proposal-builder-amount", "1")
        tapButton("proposal-builder-next")
        waitForButton("selector-field-signer")
        capture("19-create-transfer-review")

        scrollToButton("selector-field-signer", in: app)
        tapButton("selector-field-signer")
        waitForScreen("screen.selector-sheet")
        capture("20-selector-signer")
        tapButton("selector-option-0")
        waitForScreen("screen.create-transfer-proposal")

        tapFirstButton("Review and Sign")
        waitForScreen("screen.proposal-creation-review")
        waitForElement("proposal-creation-hold-button")
        capture("21-create-transfer-signing-sheet")
        longPressButton("proposal-creation-hold-button", duration: 1.8)
        waitForScreen("screen.proposal-creation-result")
        capture("22-create-transfer-receipt")
    }

    func testDemoProposalBuilderValidationStates() {
        launchDemo(profile: "appstore")
        openFirstVault()

        tapFirstButton("Propose")
        waitForScreen("screen.create-transfer-proposal")
        tapButton("proposal-builder-next")
        typeText("proposal-builder-recipient", "not-a-solana-address")
        capture("23-create-transfer-invalid-recipient")

        tapButton(CosignUITestCopy.clearRecipientAddress)
        typeText("proposal-builder-recipient", CosignUITestCopy.demoRecipient)
        tapButton("proposal-builder-next")
        typeText("proposal-builder-amount", "999999")
        capture("24-create-transfer-insufficient-balance")
    }

    func testDemoProposalStatusStates() {
        launchDemo(profile: "appstore")
        openFirstSquadProposals()

        captureProposalDetail(row: 1, name: "25-proposal-active-known")
        captureProposalDetail(row: 2, name: "26-proposal-approved-ready")
        captureProposalDetail(row: 3, name: "27-proposal-config")
        captureProposalDetail(row: 4, name: "28-proposal-unknown")
        captureProposalDetail(row: 5, name: "29-proposal-executed")
    }

    func testDemoHighRiskTypeToConfirm() {
        launchDemo(profile: "appstore")
        openFirstSquadProposals()

        // Row 4: unknown-program proposal (index 11), which triggers the high-risk
        // type-to-confirm gate. Row 0 is now the config-permission proposal (index 15).
        tapButton("proposal-preview-row-4")
        waitForScreen("screen.proposal-detail")
        capture("30-high-risk-active-detail")

        tapButton("proposal-sticky-action-approve")
        // High-risk uses a type-the-phrase gate (not a hold rail); the action
        // button stays disabled until the confirmation phrase is typed.
        waitForElement("proposal-signing-confirmation-field")
        capture("31-high-risk-type-to-confirm")
    }
}

// MARK: - Configuration changes section

final class ConfigPermissionProposalUITests: DemoWalkthroughUITestCase {
    func testDemoConfigPermissionProposalDetail() {
        launchDemo(profile: "appstore")
        openFirstSquadProposals()

        // Row 0 is the config-permission proposal (index 15, highest = newest):
        // a remove+add of the same key collapses to one permission-diff row, a new
        // voting member adds an Add row, and the enlarged signer pool produces the
        // derived signing-power (approval-ratio) row. Verifies the grouped
        // "Configuration changes" section.
        tapButton("proposal-preview-row-0")
        waitForScreen("screen.proposal-detail")
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        capture("82-config-permission-diff")
    }
}

// MARK: - Signer management + null states

final class SignerFlowUITests: DemoWalkthroughUITestCase {
    func testDemoSignerManagementSurfaces() {
        launchDemo(profile: "appstore")
        waitForScreen("screen.signers")
        tapButton("Settings")
        waitForScreen("screen.settings")
        tapButton("settings-network-row")
        waitForScreen("screen.network-settings")
        capture("36-network-settings")

        launchDemo(profile: "appstore")
        waitForScreen("screen.signers")
        tapButton("signer-row-0")
        waitForScreen("screen.signer-home")
        tapButton("Signer Settings")
        waitForScreen("screen.signer-detail")
        capture("37-signer-detail")

        captureAddSignerFresh(
            option: "hotWallet",
            screen: "screen.add-hot-wallet",
            chooserName: "32-add-signer-chooser",
            name: "33-add-hot-wallet"
        )

    }

    func testDemoImportWalletFlow() {
        launchDemo(profile: "appstore")
        waitForScreen("screen.signers")
        tapButton("signer-add-cta")
        waitForScreen("screen.add-signer-chooser")
        tapButton("signer-option-hotWallet")
        waitForScreen("screen.add-hot-wallet")
        capture("40-add-hot-wallet-create-or-import")

        tapButton("segment-import")
        waitForElement("hot-wallet-recovery-grid")
        waitForButton("hot-wallet-paste-phrase")
        capture("41-import-recovery-phrase")
    }

    func testDemoNullStatesWalkthroughLoadsEmptySurfaces() {
        launchDemo(profile: "nosigners")
        waitForScreen("screen.signers")
        capture("00-null-no-signers")
        app.terminate()

        launchDemo(profile: "nullstates")
        waitForScreen("screen.signers")
        capture("01-null-signers")

        tapButton("signer-row-0")
        waitForScreen("screen.signer-home")
        capture("02-null-signer-home")

        tapButton("signer-home-squad-row-0")
        waitForScreen("screen.squad-detail")
        capture("03-null-empty-portfolio")

        tapButton("vault-row-0")
        waitForScreen("screen.vault-detail")
        capture("04-null-vault-tokens")
        tapButton("tab-nfts")
        capture("05-null-vault-nfts")
        navigateBack()
        waitForScreen("screen.squad-detail")

        tapButton("tab-proposals")
        capture("06-null-proposals")
        tapButton("tab-activity")
        capture("07-null-activity")
        navigateBack()
        waitForScreen("screen.signer-home")

        tapButton("signer-home-squad-row-1")
        waitForScreen("screen.squad-detail")
        capture("08-null-no-vaults")
        navigateBack()
        waitForScreen("screen.signer-home")
        navigateBack()
        waitForScreen("screen.signers")

        tapButton("signer-row-2")
        waitForScreen("screen.signer-home")
        capture("09-null-no-squads")

        let createCTA = app.buttons["squads-empty-create-cta"]
        XCTAssertTrue(createCTA.waitForExistence(timeout: 60), "Missing create-squad CTA")
        createCTA.tap()
        waitForScreen("screen.create-squad")
        waitForScreen("create-squad-step-funding")
        capture("42-create-squad-funding")

        tapFirstButton("Next")
        waitForScreen("create-squad-step-members")
        capture("43-create-squad-members")

        tapFirstButton("Next")
        waitForScreen("create-squad-step-threshold")
        capture("44-create-squad-threshold")

        tapFirstButton("Next")
        waitForScreen("create-squad-step-review")
        capture("45-create-squad-review")
    }
}

// MARK: - Broadcast-failure demo flows

final class BroadcastFailureFlowUITests: DemoWalkthroughUITestCase {
    /// Captures the retryable broadcast-error sheet (attempt 1), then taps Retry
    /// and verifies the receipt appears on success.
    func testDemoBroadcastFailureRetryable() {
        launchDemo(profile: "appstore", extraArgs: ["--broadcast-failure"])
        openFirstSquadProposals()

        tapButton("proposal-preview-row-1")
        waitForScreen("screen.proposal-detail")
        tapButton("proposal-sticky-action-approveAndExecute")
        waitForElement("proposal-signing-hold-button")
        longPressButton("proposal-signing-hold-button", duration: 1.8)
        waitForScreen("screen.broadcast-error")
        capture("83-broadcast-error-retryable")

        // Title-based lookup is reliable for sheet buttons with custom button styles.
        tapFirstButton(CosignUITestCopy.retryBroadcast)
        waitForText("Approved & executed")
    }

    /// Captures the terminal broadcast-error sheet by retrying until attempt 3.
    func testDemoBroadcastFailureTerminal() {
        launchDemo(profile: "appstore", extraArgs: ["--broadcast-failure-terminal"])
        openFirstSquadProposals()

        tapButton("proposal-preview-row-1")
        waitForScreen("screen.proposal-detail")
        tapButton("proposal-sticky-action-approveAndExecute")
        waitForElement("proposal-signing-hold-button")
        longPressButton("proposal-signing-hold-button", duration: 1.8)
        waitForScreen("screen.broadcast-error")

        // Retry twice to reach attempt 3 (the terminal threshold).
        tapFirstButton(CosignUITestCopy.retryBroadcast)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        tapFirstButton(CosignUITestCopy.retryBroadcast)
        waitForText(CosignUITestCopy.stillCantReachNetwork)
        capture("84-broadcast-error-terminal")
    }
}

// MARK: - Partial-receipt capture

final class PartialReceiptUITests: DemoWalkthroughUITestCase {
    /// Captures the partial-broadcast receipt: approve lands, execute does not broadcast,
    /// user dismisses the broadcast-error sheet and sees "Approval recorded".
    func testDemoPartialBroadcastReceipt() {
        launchDemo(profile: "appstore", extraArgs: ["--broadcast-failure-execute-only"])
        openFirstSquadProposals()

        tapButton("proposal-preview-row-1")
        waitForScreen("screen.proposal-detail")
        tapButton("proposal-sticky-action-approveAndExecute")
        waitForElement("proposal-signing-hold-button")
        longPressButton("proposal-signing-hold-button", duration: 1.8)
        waitForScreen("screen.broadcast-error")
        tapFirstButton(CosignUITestCopy.dismissBroadcastError)
        waitForScreen("screen.partial-receipt")
        capture("85-partial-receipt")
    }
}

// MARK: - Signing-tally capture

final class SigningTallyUITests: DemoWalkthroughUITestCase {
    /// Captures the signer-home identity header with the mint "N signed here" chip
    /// and the Approved recent-activity row from the Operations squad.
    func testDemoSigningTallyCapture() {
        launchDemo(profile: "appstore", extraArgs: ["--signing-tally-seed=7"])
        waitForScreen("screen.signers")
        tapButton("signer-row-0")
        waitForScreen("screen.signer-home")
        capture("86-signer-home-tally")
    }
}

// MARK: - Devnet live-relay walkthrough

final class DevnetWalkthroughUITests: DemoWalkthroughUITestCase {
    /// Drives the real CosignDevnet build against the deployed relay + a live
    /// devnet fixture. Seeded by the fixture member's keypair, passed in via
    /// `TEST_RUNNER_COSIGN_DEVNET_SEED` (hex of a 64-byte keypair) so no secret
    /// is committed. The on-chain co-sign at the end is best-effort.
    func testDevnetWalkthroughAgainstLiveRelay() throws {
        let seed = ProcessInfo.processInfo.environment["COSIGN_DEVNET_SEED"] ?? ""
        try XCTSkipIf(seed.isEmpty, "set TEST_RUNNER_COSIGN_DEVNET_SEED to a 64-byte keypair hex")

        app = XCUIApplication(bundleIdentifier: "com.hackshare.cosign.devnet")
        app.launchArguments = ["--cosign-seed-signer=\(seed)", "--ui-testing"]
        app.launch()

        waitForScreen("screen.signers")
        waitForButton("signer-row-0")
        capture("01-devnet-signers")

        tapButton("signer-row-0")
        waitForScreen("screen.signer-home")
        waitForButton("signer-home-squad-row-0")
        capture("02-devnet-signer-home")

        tapButton("signer-home-squad-row-0")
        waitForScreen("screen.squad-detail")
        waitForButton("vault-row-0")
        capture("03-devnet-squad")

        tapButton("vault-row-0")
        waitForScreen("screen.vault-detail")
        capture("04-devnet-vault-usd")
        navigateBack()
        waitForScreen("screen.squad-detail")

        tapButton("tab-proposals")
        waitForButton("proposal-preview-row-0")
        tapButton("proposal-preview-row-0")
        waitForScreen("screen.proposal-detail")
        capture("05-devnet-proposal-detail")

        let coSign = app.buttons["proposal-sticky-action-approveAndExecute"]
        if coSign.waitForExistence(timeout: 60) {
            coSign.tap()
            if app.buttons["proposal-signing-hold-button"].waitForExistence(timeout: 60) {
                capture("06-devnet-signing-sheet")
                longPressButton("proposal-signing-hold-button", duration: 1.8)
                _ = app.staticTexts["Approved & executed"].waitForExistence(timeout: 45)
                capture("07-devnet-after-cosign")
            }
        }
    }
}

// MARK: - Pricing: deltas + freshness ladder

final class PricingUITests: DemoWalkthroughUITestCase {
    func testVaultDeltaCaptures() {
        launchDemo(profile: "appstore")
        openFirstVault()
        capture("83-vault-deltas")
    }

    func testPriceFreshnessCaptures() {
        app.launchArguments = [
            "--cosign-demo=appstore",
            "--cosign-demo-reset",
            "--ui-testing",
            "--price-age-seconds=300"
        ]
        app.launch()
        openFirstVault()
        capture("84-price-freshness")
    }
}

// MARK: - File-scope utilities

private func scrollToButton(_ identifier: String, in app: XCUIApplication, maxAttempts: Int = 4) {
    let button = app.buttons[identifier]
    XCTAssertTrue(button.waitForExistence(timeout: 60), "Missing button \(identifier)")
    for _ in 0 ..< maxAttempts where !button.isHittable {
        app.swipeUp()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    XCTAssertTrue(button.isHittable, "Button \(identifier) is not hittable")
}

private func dismissKeyboardIfPresent(in app: XCUIApplication) {
    let keyboard = app.keyboards.firstMatch
    guard keyboard.exists else {
        return
    }

    let doneButton = app.buttons["proposal-builder-keyboard-done"]
    if doneButton.waitForExistence(timeout: 1) {
        doneButton.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        return
    }

    keyboard.swipeDown()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))

    if keyboard.exists {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
}

private enum CosignUITestCopy {
    static let cancel = "Cancel"
    static let close = "Close"
    static let clearRecipientAddress = "Clear Recipient Address"
    static let demoRecipient = "EEotmEULbaiQdvxKAswEAiHNB7nuhA6LV5ypbM9NNHbM"
    static let retryBroadcast = "Retry broadcast"
    static let stillCantReachNetwork = "Still can't reach the network"
    static let dismissBroadcastError = "Dismiss"
}
