import Foundation

extension CosignCopy.YubiKey {
    static let connectChromeTitle = String(localized: "Connect YubiKey", bundle: .module)
    static let confirmChromeTitle = String(localized: "Confirm", bundle: .module)

    static let tapEyebrow = String(localized: "Hardware signer", bundle: .module)
    static let tapTitle = String(localized: "Tap your YubiKey", bundle: .module)
    static let tapSubtitle = String(
        localized: "Hold the key to the top of your phone, or insert it into the port.",
        bundle: .module
    )
    static let listeningNFC = String(localized: "Listening for NFC…", bundle: .module)
    static let listeningWired = String(localized: "Insert and hold your key", bundle: .module)
    static let useWiredButton = String(localized: "Use USB instead", bundle: .module)
    static let useNFCButton = String(localized: "Tap over NFC instead", bundle: .module)
    static let continueButton = String(localized: "Continue", bundle: .module)
    static let labelFieldTitle = String(localized: "Label", bundle: .module)

    static let pinEyebrow = String(localized: "Step 2 of 3", bundle: .module)
    static let pinTitle = String(localized: "Enter PIN", bundle: .module)
    static let pinDeleteLabel = String(localized: "Delete", bundle: .module)
    static let pinDeleteAccessibility = String(localized: "Delete digit", bundle: .module)

    static let touchEyebrow = String(localized: "Step 3 of 3", bundle: .module)
    static let touchTitle = String(localized: "Touch your YubiKey", bundle: .module)
    static let touchSubtitle = String(
        localized: "Touch the gold disc to prove you are present and approve the address.",
        bundle: .module
    )
    static let waitingForTouch = String(localized: "Waiting for touch…", bundle: .module)

    static let readyTitle = String(localized: "YubiKey connected", bundle: .module)
    static let readySubtitle = String(localized: "This signer is ready to approve proposals.", bundle: .module)
    static let hardwareTag = String(localized: "HARDWARE", bundle: .module)

    static func pinAttemptsRemaining(_ count: Int) -> String {
        String(localized: "\(count) attempt\(count == 1 ? "" : "s") remaining before the key locks.", bundle: .module)
    }

    enum Recovery {
        static let wrongPINTitle = String(localized: "Wrong PIN", bundle: .module)
        static let wrongPINAction = String(localized: "Re-enter PIN", bundle: .module)

        static let pinLockedTitle = String(localized: "Key locked", bundle: .module)
        static let pinLockedMessage = String(
            localized: "Too many wrong PINs. Reset the PIN with your PUK using YubiKey Manager.",
            bundle: .module
        )
        static let pinLockedAction = String(localized: "Start over", bundle: .module)

        static let noKeyTitle = String(localized: "No key detected", bundle: .module)
        static let noKeyMessage = String(localized: "NFC found no key, or the port is empty.", bundle: .module)
        static let noKeyAction = String(localized: "Tap again", bundle: .module)

        static let nfcUnavailableTitle = String(localized: "NFC unavailable", bundle: .module)
        static let nfcUnavailableMessage = String(
            localized: "This device can't reach the key over NFC. Insert it over USB instead.",
            bundle: .module
        )
        static let nfcUnavailableAction = String(localized: "Use USB", bundle: .module)

        static let touchTimedOutTitle = String(localized: "Touch timed out", bundle: .module)
        static let touchTimedOutMessage = String(localized: "No touch registered in time.", bundle: .module)
        static let touchTimedOutAction = String(localized: "Retry", bundle: .module)

        static let lostConnectionTitle = String(localized: "Connection lost", bundle: .module)
        static let lostConnectionMessage = String(
            localized: "The key moved away or the session ended before it finished.",
            bundle: .module
        )
        static let lostConnectionAction = String(localized: "Reconnect", bundle: .module)

        static let notProvisionedTitle = String(localized: "No signing key on this YubiKey", bundle: .module)
        static let notProvisionedMessage =
            String(
                localized: "Slot 9C has no Ed25519 key. Provision one with YubiKey Manager, then start over.",
                bundle: .module
            )
        static let notProvisionedAction = String(localized: "Start over", bundle: .module)

        static let mismatchTitle = String(localized: "Address mismatch", bundle: .module)
        static let mismatchMessage = String(
            localized: "The key returned a different address. Never approve a mismatch.",
            bundle: .module
        )
        static let mismatchAction = String(localized: "Start over", bundle: .module)

        static let alreadyAddedTitle = String(localized: "Already added", bundle: .module)
        static let alreadyAddedMessage = String(
            localized: "This YubiKey address is already a signer on this device.",
            bundle: .module
        )

        static func wrongPINMessage(retriesRemaining: Int) -> String {
            String(
                localized: "\(retriesRemaining) attempt\(retriesRemaining == 1 ? "" : "s") remaining before the key locks itself.",
                bundle: .module
            )
        }
    }
}
