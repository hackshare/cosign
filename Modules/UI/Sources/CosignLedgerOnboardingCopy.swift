import Foundation

extension CosignCopy.Ledger {
    static let connectChromeTitle = "Connect Ledger"

    static let checklistEyebrow = "Hardware signer"
    static let checklistTitle = "Before we scan"
    static let checklistSubtitle = "Get your Ledger ready, then start the Bluetooth scan."
    static let checklistStepUnlock = "Unlock your Ledger with its PIN"
    static let checklistStepSolanaApp = "Open the Solana app on the device"
    static let checklistStepBluetooth = "Turn Bluetooth on"
    static let checklistStepProximity = "Hold the device near your phone"
    static let privacyNote =
        "Cosign never sees your recovery phrase — the Ledger signs on-device and returns only the signature."
    static let startScanButton = "Start scan"
    static let labelFieldTitle = "Label"

    static let searchingTitle = "Searching for devices…"
    static let searchingSubtitle = "Keep the Ledger unlocked and nearby"
    static let connectButton = "Connect"

    static let verifyEyebrow = "Step 4 of 4"
    static let verifyTitle = "Confirm on your Ledger"
    static let verifySubtitle = "Check the address on the device screen matches the one below, then approve."
    static let addressFieldTitle = "Address"
    static let waitingForApproval = "Waiting for approval on device"
    static let verifyCautionNote =
        "Reject on the device if the address does not match exactly — never approve a mismatch."

    static let readyTitle = "Ledger connected"
    static let readySubtitle = "This signer is ready to approve proposals."
    static let hardwareTag = "HARDWARE"

    static func foundSectionTitle(count: Int) -> String {
        "Found · \(count)"
    }

    static func connectingTitle(deviceName: String) -> String {
        "Connecting to \(deviceName)…"
    }

    static func deviceSubtitle(rssi: Int) -> String {
        "Bluetooth signer · \(rssi) dBm"
    }

    enum Recovery {
        static let bluetoothOffTitle = "Bluetooth is off"
        static let bluetoothOffMessage = "Cosign needs Bluetooth to reach the Ledger."
        static let bluetoothOffAction = "Open Settings"

        static let permissionDeniedTitle = "Bluetooth permission denied"
        static let permissionDeniedMessage = "The app was denied Bluetooth access."
        static let permissionDeniedAction = "Allow in Settings"

        static let deviceLockedTitle = "Device is locked"
        static let deviceLockedMessage = "Unlock the Ledger with its PIN to continue."
        static let deviceLockedAction = "Retry scan"

        static let solanaAppTitle = "Solana app not open"
        static let solanaAppMessage = "Open the Solana app on the device, not the dashboard or another app."
        static let solanaAppAction = "Retry"

        static let lostConnectionTitle = "Out of range / lost connection"
        static let lostConnectionMessage = "The device moved too far or went to sleep."
        static let lostConnectionAction = "Reconnect"

        static let timedOutTitle = "Timed out"
        static let timedOutMessage = "No response from the device in time."
        static let timedOutAction = "Try again"

        static let noDevicesTitle = "No Ledger found"
        static let noDevicesMessage = "No Ledger was in range. Keep it unlocked and nearby, then try again."
        static let noDevicesAction = "Try again"

        static let mismatchTitle = "Address mismatch"
        static let mismatchMessage = "The device returned a different address. Never approve a mismatch."
        static let mismatchAction = "Start over"

        static let alreadyAddedTitle = "Already added"
        static let alreadyAddedMessage = "This Ledger address is already a signer on this device."
    }
}
