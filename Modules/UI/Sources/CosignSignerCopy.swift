import Core
import Foundation

extension CosignCopy {
    enum SignerDetail {
        static let navigationTitle = String(localized: "Signer", bundle: .module)
        static let labelRowTitle = String(localized: "Label", bundle: .module)
        static let typeRowTitle = String(localized: "Type", bundle: .module)
        static let addedRowTitle = String(localized: "Added", bundle: .module)
        static let memberAddressTitle = String(localized: "Member address", bundle: .module)
        static let deviceSectionTitle = String(localized: "Device", bundle: .module)
        static let removeSignerTitle = String(localized: "Remove Signer", bundle: .module)
        static let storedOnDeviceHeader = String(localized: "Signer · stored on-device", bundle: .module)
        static let hardwareHeader = String(localized: "Signer · hardware", bundle: .module)

        static let backupSectionTitle = String(localized: "Backup", bundle: .module)
        static let backedUpRowTitle = String(localized: "Backed up", bundle: .module)
        static let backedUpRowDetailPlain = String(localized: "Recovery phrase confirmed", bundle: .module)
        static let notBackedUpRowTitle = String(localized: "Not backed up", bundle: .module)
        static let notBackedUpRowDetail = String(localized: "Back up before this wallet can sign", bundle: .module)
        static let revealRowTitle = String(localized: "Reveal recovery phrase", bundle: .module)
        static let revealRowDetail = String(localized: "Requires Face ID · copy disabled", bundle: .module)

        static let keySourceSectionTitle = String(localized: "Key source", bundle: .module)
        static let importedKeyRowTitle = String(localized: "Imported key", bundle: .module)
        static let importedKeyRowDetail = String(localized: "You hold this key · no recovery phrase", bundle: .module)
        static let revealSecretKeyRowTitle = String(localized: "Reveal secret key", bundle: .module)
        static let removeImportedMessage =
            String(
                localized: "This removes the signer and deletes its key from the Keychain. It is only re-importable with the secret key — keep your copy safe.",
                bundle: .module
            )

        static func revealSecretKeyPrompt(label: String) -> String {
            String(localized: "Reveal secret key for \(label)", bundle: .module)
        }

        static func importedTypeValue(base: String) -> String {
            String(localized: "\(base) · Imported", bundle: .module)
        }

        static func backedUpRowDetail(date: Date) -> String {
            String(
                localized: "Recovery phrase confirmed · \(date.formatted(.dateTime.month(.abbreviated).day()))",
                bundle: .module
            )
        }

        static func revealPrompt(label: String) -> String {
            String(localized: "Reveal recovery phrase for \(label)", bundle: .module)
        }

        static func headerTitle(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                storedOnDeviceHeader
            }
        }
    }
}

extension CosignCopy {
    enum RecoveryPhraseReveal {
        static let headerTitle = String(localized: "Recovery phrase", bundle: .module)
        static let sectionTitle = String(localized: "Recovery phrase", bundle: .module)
        static let blurredMessage =
            String(localized: "Tap reveal to show your recovery phrase. Make sure no one is watching.", bundle: .module)
        static let revealedMessage =
            String(
                localized: "Anyone with these words controls this wallet. Never share or screenshot them.",
                bundle: .module
            )
        static let revealButtonTitle = String(localized: "Reveal", bundle: .module)
        static let doneButtonTitle = String(localized: "Done", bundle: .module)
        static let keychainNote = String(
            localized: "Stored in the iOS Keychain · never leaves this device · copy disabled.",
            bundle: .module
        )
        static let unavailableTitle = String(localized: "No phrase stored", bundle: .module)
        static let unavailableMessage =
            String(
                localized: "This signer has no recovery phrase on this device. It was imported as a raw key.",
                bundle: .module
            )

        static func wordOrdinal(_ index: Int) -> String {
            "\(index)."
        }
    }
}

extension CosignCopy {
    enum SecretKeyReveal {
        static let headerTitle = String(localized: "Secret key", bundle: .module)
        static let sectionTitle = String(localized: "Secret key", bundle: .module)
        static let placeholder = String(localized: "[ •••• ]", bundle: .module)
        static let blurredMessage =
            String(localized: "Tap reveal to show your secret key. Make sure no one is watching.", bundle: .module)
        static let revealedMessage =
            String(
                localized: "Anyone with this key controls this wallet. Never share or screenshot it.",
                bundle: .module
            )
        static let revealButtonTitle = String(localized: "Reveal", bundle: .module)
        static let doneButtonTitle = String(localized: "Done", bundle: .module)
        static let keychainNote = String(
            localized: "Stored in the iOS Keychain · never leaves this device · copy disabled.",
            bundle: .module
        )
        static let unavailableTitle = String(localized: "No key stored", bundle: .module)
        static let unavailableMessage = String(
            localized: "This signer's secret key is not available on this device.",
            bundle: .module
        )
    }
}

extension CosignCopy {
    enum SignerDiagnostics {
        static let diagnosticsSectionTitle = String(localized: "Diagnostics", bundle: .module)
        static let testFailedTitle = String(localized: "Test failed", bundle: .module)
        static let checkingKeychainStatus = String(localized: "Checking Keychain item...", bundle: .module)
        static let diagnosticPayload = "Cosign signer diagnostic"
        static let hotWalletReadyTitle = String(localized: "Hot wallet ready", bundle: .module)
        static let hotWalletReadyMessage = String(
            localized: "The Keychain item loaded and produced a valid signature.",
            bundle: .module
        )
        static let missingHotWalletKeychainReference =
            String(localized: "This hot wallet is missing its Keychain reference.", bundle: .module)
        static let invalidHotWalletSignature =
            String(
                localized: "The hot wallet produced a signature that did not verify against the saved address.",
                bundle: .module
            )

        static func buttonTitle(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                String(localized: "Test Hot Wallet", bundle: .module)
            }
        }
    }
}

extension CosignCopy {
    enum MnemonicConfirmation {
        static let flowTitle = String(localized: "Confirm Backup", bundle: .module)
        static let backButtonTitle = String(localized: "Back", bundle: .module)
        static let sectionTitle = String(localized: "Confirm backup", bundle: .module)
        static let title = String(localized: "Check Words", bundle: .module)
        static let selectedWordsSectionTitle = String(localized: "Selected words", bundle: .module)
        static let mnemonicWordsSectionTitle = String(localized: "Mnemonic words", bundle: .module)
        static let confirmButtonTitle = String(localized: "Confirm", bundle: .module)
        static let backToMnemonicTitle = String(localized: "Back to Mnemonic", bundle: .module)
        static let emptySelectionPrompt = String(localized: "Tap a word below", bundle: .module)

        static func wordTitle(index: Int) -> String {
            String(localized: "Word \(index)", bundle: .module)
        }
    }
}
