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
            case .ledger, .yubikey:
                hardwareHeader
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
        static let yubiKeySectionTitle = String(localized: "YubiKey", bundle: .module)
        static let yubiKeyMessage =
            String(
                localized: "The connected YubiKey must expose the saved Ed25519 key from the PIV signature slot (9C).",
                bundle: .module
            )
        static let diagnosticsSectionTitle = String(localized: "Diagnostics", bundle: .module)
        static let testFailedTitle = String(localized: "Test failed", bundle: .module)
        static let checkingKeychainStatus = String(localized: "Checking Keychain item...", bundle: .module)
        static let diagnosticPayload = "Cosign signer diagnostic"
        static let hotWalletReadyTitle = String(localized: "Hot wallet ready", bundle: .module)
        static let hotWalletReadyMessage = String(
            localized: "The Keychain item loaded and produced a valid signature.",
            bundle: .module
        )
        static let verifyingAddressStatus = String(localized: "Verifying saved address...", bundle: .module)
        static let blindSigningEnabled = String(localized: "enabled", bundle: .module)
        static let blindSigningDisabled = String(localized: "disabled", bundle: .module)
        static let ledgerReadyTitle = String(localized: "Ledger ready", bundle: .module)
        static let yubiKeyTestPrompt = String(
            localized: "Hold your YubiKey near this iPhone to test it.",
            bundle: .module
        )
        static let yubiKeyReadyTitle = String(localized: "YubiKey ready", bundle: .module)
        static let missingHotWalletKeychainReference =
            String(localized: "This hot wallet is missing its Keychain reference.", bundle: .module)
        static let invalidHotWalletSignature =
            String(
                localized: "The hot wallet produced a signature that did not verify against the saved address.",
                bundle: .module
            )
        static let noLedgerDevices = String(localized: "No Ledger devices were found.", bundle: .module)

        static func buttonTitle(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                String(localized: "Test Hot Wallet", bundle: .module)
            case .ledger:
                String(localized: "Test Ledger Connection", bundle: .module)
            case .yubikey:
                String(localized: "Test YubiKey Connection", bundle: .module)
            }
        }

        static func ledgerReadyMessage(deviceName: String, version: String, blindSigning: String) -> String {
            String(
                localized: "Connected to \(deviceName). Solana app \(version) matched the saved address. Blind signing is \(blindSigning).",
                bundle: .module
            )
        }

        static func yubiKeyReadyMessage(details: String) -> String {
            String(localized: "The PIV signature slot matched the saved address. \(details)", bundle: .module)
        }

        static func sourceDetail(_ source: String) -> String {
            String(localized: "Source: \(source).", bundle: .module)
        }

        static func keyOriginDetail(generatedOnYubiKey: Bool) -> String {
            String(
                localized: "Key origin: \(generatedOnYubiKey ? "generated on YubiKey" : "imported").",
                bundle: .module
            )
        }

        static func addressMismatch(expected: String, actual: String) -> String {
            String(
                localized: "The connected signer address does not match the saved signer. Expected \(expected), got \(actual).",
                bundle: .module
            )
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

extension CosignCopy {
    enum Ledger {
        static let defaultLabel = String(localized: "My Ledger", bundle: .module)
        static let doneButtonTitle = String(localized: "Done", bundle: .module)

        static func scanningStatus() -> String {
            String(localized: "Scanning for Ledger devices...", bundle: .module)
        }

        static func connectingStatus(deviceName: String) -> String {
            String(localized: "Connecting to \(deviceName)...", bundle: .module)
        }
    }
}

extension CosignCopy {
    enum YubiKey {
        static let defaultLabel = String(localized: "My YubiKey", bundle: .module)
        static let doneButtonTitle = String(localized: "Done", bundle: .module)
        static let tapPrompt = String(localized: "Hold your YubiKey near this iPhone to add it.", bundle: .module)

        static func connectingStatus(transport: String) -> String {
            String(localized: "Connecting to \(transport)...", bundle: .module)
        }
    }
}

extension CosignCopy {
    enum YubiKeySigning {
        static let pluggedInTransportTitle = String(localized: "Plugged In", bundle: .module)
        static let tapTransportTitle = String(localized: "Tap", bundle: .module)
        static let pluggedInTransportStatus = String(localized: "plugged-in YubiKey", bundle: .module)
        static let nfcTransportStatus = String(localized: "NFC YubiKey", bundle: .module)
        static let sectionTitle = String(localized: "YubiKey", bundle: .module)
        static let pinPlaceholder = String(localized: "PIN", bundle: .module)
        static let pinLengthMessage = String(localized: "YubiKey PIV PINs must be 6 to 8 characters.", bundle: .module)
        static let tapPrompt = String(localized: "Hold your YubiKey near this iPhone to sign.", bundle: .module)
        static let connectingStatusPrefix = String(localized: "Connecting to", bundle: .module)
        static let signStatus = String(localized: "Sign with your YubiKey.", bundle: .module)
        static let checkFailedTitle = String(localized: "YubiKey check failed", bundle: .module)
        static let unsupportedKeyTitle = String(localized: "Unsupported YubiKey key", bundle: .module)
        static let keyNotFoundTitle = String(localized: "YubiKey key not found", bundle: .module)
        static let keyNotReadableTitle = String(localized: "YubiKey key not readable", bundle: .module)

        static func connectingStatus(transport: String) -> String {
            String(localized: "\(connectingStatusPrefix) \(transport)...", bundle: .module)
        }

        static func unsupportedKeyMessage(slotName: String) -> String {
            String(
                localized: "The \(slotName) has a key, but it is not Ed25519. Provision or import an Ed25519 key in slot 9C with YubiKey Manager, then try again. Cosign will not overwrite hardware keys.",
                bundle: .module
            )
        }

        static func keyNotFoundMessage(slotName: String) -> String {
            String(
                localized: "Cosign could not find an Ed25519 public key in the \(slotName). Provision or import an Ed25519 key in slot 9C with YubiKey Manager, then try again.",
                bundle: .module
            )
        }

        static func keyNotReadableMessage(
            slotName: String,
            metadataError: String,
            certificateError: String
        ) -> String {
            String(
                localized: "Cosign could not read an Ed25519 public key from the \(slotName). Confirm the PIV app is enabled and slot 9C contains an Ed25519 key. Metadata: \(metadataError) Certificate: \(certificateError)",
                bundle: .module
            )
        }
    }
}
