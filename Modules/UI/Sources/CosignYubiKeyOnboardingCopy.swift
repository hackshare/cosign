import Foundation

extension CosignCopy.YubiKey {
    static let connectChromeTitle = "Connect YubiKey"
    static let confirmChromeTitle = "Confirm"

    static let tapEyebrow = "Hardware signer"
    static let tapTitle = "Tap your YubiKey"
    static let tapSubtitle = "Hold the key to the top of your phone, or insert it into the port."
    static let listeningNFC = "Listening for NFC…"
    static let listeningWired = "Insert and hold your key"
    static let useWiredButton = "Use USB instead"
    static let useNFCButton = "Tap over NFC instead"
    static let continueButton = "Continue"
    static let labelFieldTitle = "Label"

    static let pinEyebrow = "Step 2 of 3"
    static let pinTitle = "Enter PIN"
    static let pinDeleteLabel = "Delete"
    static let pinDeleteAccessibility = "Delete digit"

    static let touchEyebrow = "Step 3 of 3"
    static let touchTitle = "Touch your YubiKey"
    static let touchSubtitle = "Touch the gold disc to prove you are present and approve the address."
    static let waitingForTouch = "Waiting for touch…"
    static let verifyingPIN = "Verifying PIN…"
    static let addressFieldTitle = "Address"

    static let readyTitle = "YubiKey connected"
    static let readySubtitle = "This signer is ready to approve proposals."
    static let hardwareTag = "HARDWARE"

    static func pinAttemptsRemaining(_ count: Int) -> String {
        "\(count) attempt\(count == 1 ? "" : "s") remaining before the key locks."
    }

    enum Recovery {
        static let wrongPINTitle = "Wrong PIN"
        static let wrongPINAction = "Re-enter PIN"

        static let pinLockedTitle = "Key locked"
        static let pinLockedMessage = "Too many wrong PINs. Reset the PIN with your PUK using YubiKey Manager."
        static let pinLockedAction = "Start over"

        static let noKeyTitle = "No key detected"
        static let noKeyMessage = "NFC found no key, or the port is empty."
        static let noKeyAction = "Tap again"

        static let nfcUnavailableTitle = "NFC unavailable"
        static let nfcUnavailableMessage = "This device can't reach the key over NFC. Insert it over USB instead."
        static let nfcUnavailableAction = "Use USB"

        static let touchTimedOutTitle = "Touch timed out"
        static let touchTimedOutMessage = "No touch registered in time."
        static let touchTimedOutAction = "Retry"

        static let lostConnectionTitle = "Connection lost"
        static let lostConnectionMessage = "The key moved away or the session ended before it finished."
        static let lostConnectionAction = "Reconnect"

        static let notProvisionedTitle = "No signing key on this YubiKey"
        static let notProvisionedMessage =
            "Slot 9C has no Ed25519 key. Provision one with YubiKey Manager, then start over."
        static let notProvisionedAction = "Start over"

        static let mismatchTitle = "Address mismatch"
        static let mismatchMessage = "The key returned a different address. Never approve a mismatch."
        static let mismatchAction = "Start over"

        static let alreadyAddedTitle = "Already added"
        static let alreadyAddedMessage = "This YubiKey address is already a signer on this device."

        static func wrongPINMessage(retriesRemaining: Int) -> String {
            "\(retriesRemaining) attempt\(retriesRemaining == 1 ? "" : "s") remaining before the key locks itself."
        }
    }
}
