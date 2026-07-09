import Foundation

extension CosignCopy.Ledger {
    static let connectChromeTitle = String(localized: "Connect Ledger", bundle: .module)

    static let checklistEyebrow = String(localized: "Hardware signer", bundle: .module)
    static let checklistTitle = String(localized: "Before we scan", bundle: .module)
    static let checklistSubtitle = String(
        localized: "Get your Ledger ready, then start the Bluetooth scan.",
        bundle: .module
    )
    static let checklistStepUnlock = String(localized: "Unlock your Ledger with its PIN", bundle: .module)
    static let checklistStepSolanaApp = String(localized: "Open the Solana app on the device", bundle: .module)
    static let checklistStepBluetooth = String(localized: "Turn Bluetooth on", bundle: .module)
    static let checklistStepProximity = String(localized: "Hold the device near your phone", bundle: .module)
    static let privacyNote =
        String(
            localized: "Cosign never sees your recovery phrase — the Ledger signs on-device and returns only the signature.",
            bundle: .module
        )
    static let startScanButton = String(localized: "Start scan", bundle: .module)
    static let labelFieldTitle = String(localized: "Label", bundle: .module)

    static let searchingTitle = String(localized: "Searching for devices…", bundle: .module)
    static let searchingSubtitle = String(localized: "Keep the Ledger unlocked and nearby", bundle: .module)
    static let connectButton = String(localized: "Connect", bundle: .module)

    static let verifyEyebrow = String(localized: "Step 4 of 4", bundle: .module)
    static let verifyTitle = String(localized: "Confirm on your Ledger", bundle: .module)
    static let verifySubtitle = String(
        localized: "Check the address on the device screen matches the one below, then approve.",
        bundle: .module
    )
    static let addressFieldTitle = String(localized: "Address", bundle: .module)
    static let waitingForApproval = String(localized: "Waiting for approval on device", bundle: .module)
    static let verifyCautionNote =
        String(
            localized: "Reject on the device if the address does not match exactly — never approve a mismatch.",
            bundle: .module
        )

    static let readyTitle = String(localized: "Ledger connected", bundle: .module)
    static let readySubtitle = String(localized: "This signer is ready to approve proposals.", bundle: .module)
    static let hardwareTag = String(localized: "HARDWARE", bundle: .module)

    static func foundSectionTitle(count: Int) -> String {
        String(localized: "Found · \(count)", bundle: .module)
    }

    static func connectingTitle(deviceName: String) -> String {
        String(localized: "Connecting to \(deviceName)…", bundle: .module)
    }

    static func deviceSubtitle(rssi: Int) -> String {
        String(localized: "Bluetooth signer · \(rssi) dBm", bundle: .module)
    }

    enum Recovery {
        static let bluetoothOffTitle = String(localized: "Bluetooth is off", bundle: .module)
        static let bluetoothOffMessage = String(
            localized: "Cosign needs Bluetooth to reach the Ledger.",
            bundle: .module
        )
        static let bluetoothOffAction = String(localized: "Open Settings", bundle: .module)

        static let permissionDeniedTitle = String(localized: "Bluetooth permission denied", bundle: .module)
        static let permissionDeniedMessage = String(localized: "The app was denied Bluetooth access.", bundle: .module)
        static let permissionDeniedAction = String(localized: "Allow in Settings", bundle: .module)

        static let deviceLockedTitle = String(localized: "Device is locked", bundle: .module)
        static let deviceLockedMessage = String(
            localized: "Unlock the Ledger with its PIN to continue.",
            bundle: .module
        )
        static let deviceLockedAction = String(localized: "Retry scan", bundle: .module)

        static let solanaAppTitle = String(localized: "Solana app not open", bundle: .module)
        static let solanaAppMessage = String(
            localized: "Open the Solana app on the device, not the dashboard or another app.",
            bundle: .module
        )
        static let solanaAppAction = String(localized: "Retry", bundle: .module)

        static let lostConnectionTitle = String(localized: "Out of range / lost connection", bundle: .module)
        static let lostConnectionMessage = String(
            localized: "The device moved too far or went to sleep.",
            bundle: .module
        )
        static let lostConnectionAction = String(localized: "Reconnect", bundle: .module)

        static let timedOutTitle = String(localized: "Timed out", bundle: .module)
        static let timedOutMessage = String(localized: "No response from the device in time.", bundle: .module)
        static let timedOutAction = String(localized: "Try again", bundle: .module)

        static let noDevicesTitle = String(localized: "No Ledger found", bundle: .module)
        static let noDevicesMessage = String(
            localized: "No Ledger was in range. Keep it unlocked and nearby, then try again.",
            bundle: .module
        )
        static let noDevicesAction = String(localized: "Try again", bundle: .module)

        static let mismatchTitle = String(localized: "Address mismatch", bundle: .module)
        static let mismatchMessage = String(
            localized: "The device returned a different address. Never approve a mismatch.",
            bundle: .module
        )
        static let mismatchAction = String(localized: "Start over", bundle: .module)

        static let alreadyAddedTitle = String(localized: "Already added", bundle: .module)
        static let alreadyAddedMessage = String(
            localized: "This Ledger address is already a signer on this device.",
            bundle: .module
        )
    }
}
