import Core
import Foundation

extension CosignCopy {
    enum SignerDetail {
        static let navigationTitle = "Signer"
        static let labelRowTitle = "Label"
        static let typeRowTitle = "Type"
        static let addedRowTitle = "Added"
        static let memberAddressTitle = "Member address"
        static let deviceSectionTitle = "Device"
        static let removeSignerTitle = "Remove Signer"
        static let storedOnDeviceHeader = "Signer · stored on-device"
        static let hardwareHeader = "Signer · hardware"

        static let backupSectionTitle = "Backup"
        static let backedUpRowTitle = "Backed up"
        static let backedUpRowDetailPlain = "Recovery phrase confirmed"
        static let notBackedUpRowTitle = "Not backed up"
        static let notBackedUpRowDetail = "Back up before this wallet can sign"
        static let revealRowTitle = "Reveal recovery phrase"
        static let revealRowDetail = "Requires Face ID · copy disabled"

        static func backedUpRowDetail(date: Date) -> String {
            "Recovery phrase confirmed · \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }

        static func revealPrompt(label: String) -> String {
            "Reveal recovery phrase for \(label)"
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
        static let headerTitle = "Recovery phrase"
        static let sectionTitle = "Recovery phrase"
        static let title = "Reveal"
        static let blurredMessage =
            "Tap reveal to show your recovery phrase. Make sure no one is watching."
        static let revealedMessage =
            "Anyone with these words controls this wallet. Never share or screenshot them."
        static let revealButtonTitle = "Reveal"
        static let doneButtonTitle = "Done"
        static let keychainNote = "Stored in the iOS Keychain · never leaves this device · copy disabled."
        static let unavailableTitle = "No phrase stored"
        static let unavailableMessage =
            "This signer has no recovery phrase on this device. It was imported as a raw key."

        static func wordOrdinal(_ index: Int) -> String {
            "\(index)."
        }
    }
}

extension CosignCopy {
    enum SignerDiagnostics {
        static let yubiKeySectionTitle = "YubiKey"
        static let yubiKeyMessage =
            "The connected YubiKey must expose the saved Ed25519 key from the PIV signature slot (9C)."
        static let diagnosticsSectionTitle = "Diagnostics"
        static let testFailedTitle = "Test failed"
        static let checkingKeychainStatus = "Checking Keychain item..."
        static let diagnosticPayload = "Cosign signer diagnostic"
        static let hotWalletReadyTitle = "Hot wallet ready"
        static let hotWalletReadyMessage = "The Keychain item loaded and produced a valid signature."
        static let verifyingAddressStatus = "Verifying saved address..."
        static let blindSigningEnabled = "enabled"
        static let blindSigningDisabled = "disabled"
        static let ledgerReadyTitle = "Ledger ready"
        static let yubiKeyTestPrompt = "Hold your YubiKey near this iPhone to test it."
        static let yubiKeyReadyTitle = "YubiKey ready"
        static let missingHotWalletKeychainReference =
            "This hot wallet is missing its Keychain reference."
        static let invalidHotWalletSignature =
            "The hot wallet produced a signature that did not verify against the saved address."
        static let noLedgerDevices = "No Ledger devices were found."

        static func buttonTitle(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                "Test Hot Wallet"
            case .ledger:
                "Test Ledger Connection"
            case .yubikey:
                "Test YubiKey Connection"
            }
        }

        static func ledgerReadyMessage(deviceName: String, version: String, blindSigning: String) -> String {
            "Connected to \(deviceName). Solana app \(version) matched the saved address. Blind signing is \(blindSigning)."
        }

        static func yubiKeyReadyMessage(details: String) -> String {
            "The PIV signature slot matched the saved address. \(details)"
        }

        static func sourceDetail(_ source: String) -> String {
            "Source: \(source)."
        }

        static func keyOriginDetail(generatedOnYubiKey: Bool) -> String {
            "Key origin: \(generatedOnYubiKey ? "generated on YubiKey" : "imported")."
        }

        static func addressMismatch(expected: String, actual: String) -> String {
            "The connected signer address does not match the saved signer. Expected \(expected), got \(actual)."
        }
    }
}

extension CosignCopy {
    enum MnemonicConfirmation {
        static let flowTitle = "Confirm Backup"
        static let backButtonTitle = "Back"
        static let sectionTitle = "Confirm backup"
        static let title = "Check Words"
        static let selectedWordsSectionTitle = "Selected words"
        static let mnemonicWordsSectionTitle = "Mnemonic words"
        static let confirmButtonTitle = "Confirm"
        static let backToMnemonicTitle = "Back to Mnemonic"
        static let emptySelectionPrompt = "Tap a word below"

        static func wordTitle(index: Int) -> String {
            "Word \(index)"
        }
    }
}

extension CosignCopy {
    enum Ledger {
        static let defaultLabel = "My Ledger"
        static let readyStatus = "Ready to scan."
        static let addTitle = "Add Ledger"
        static let hardwareSectionTitle = "Hardware signer"
        static let errorTitle = "Ledger Error"
        static let labelSectionTitle = "Label"
        static let deviceSectionTitle = "Device"
        static let scanningTitle = "Scanning..."
        static let noDevicesTitle = "No Ledger Devices"
        static let scanAgainTitle = "Scan Again"
        static let statusSectionTitle = "Status"
        static let ledgerAddedTitle = "Ledger Added"
        static let ledgerAddedMessage = "This Ledger address is ready to use."
        static let memberAddressTitle = "Member address"
        static let copyLedgerAddress = "Copy Ledger Address"
        static let doneButtonTitle = "Done"
        static let noDevicesStatus = "No Ledger devices found."
        static let scanFailedStatus = "Scan failed."
        static let checkingAppStatus = "Checking Solana app..."
        static let confirmAddressStatus = "Confirm the address on your Ledger."
        static let alreadyAddedError = "This Ledger address is already on this device."
        static let alreadyAddedStatus = "Ledger already added."
        static let addedStatus = "Ledger added."
        static let pairingFailedStatus = "Pairing failed."

        static func scanningStatus() -> String {
            "Scanning for Ledger devices..."
        }

        static func devicesFoundStatus(count: Int) -> String {
            "\(count) Ledger device\(count == 1 ? "" : "s") found."
        }

        static func connectingStatus(deviceName: String) -> String {
            "Connecting to \(deviceName)..."
        }

        static func rssi(_ value: Int) -> String {
            "\(value) dBm"
        }
    }
}

extension CosignCopy {
    enum YubiKey {
        static let defaultLabel = "My YubiKey"
        static let doneButtonTitle = "Done"
        static let tapPrompt = "Hold your YubiKey near this iPhone to add it."

        static func connectingStatus(transport: String) -> String {
            "Connecting to \(transport)..."
        }
    }
}

extension CosignCopy {
    enum Signers {
        static let settingsAccessibilityLabel = "Settings"
        static let title = "Signers"
        static let searchPlaceholder = "Search signers"
        static let removeSignerMenuTitle = "Remove Signer"
        static let removeSignerTitle = "Remove signer?"
        static let keepSignerTitle = "Keep Signer"
        static let connectOrCreateTitle = "Connect or create signer"
        static let copySignerAddress = "Copy Signer Address"
        static let addSignerTitle = "Add signer"
        static let addSignerSubtitle = "Choose the key you want to use for approvals."
        static let closeAccessibilityLabel = "Close"
        static let signerNotFoundTitle = "Signer Not Found"
        static let signerNotFoundMessage = "This signer is no longer on this device."
        static let signerSettingsAccessibilityLabel = "Signer Settings"
        static let pendingSquadsSubtitle = "Across this signer's Squads"
        static let unableToLoadSquadsTitle = "Unable to Load Squads"
        static let recentSectionTitle = "Recent"
        static let allClear = "All clear"
        static let loadingMembershipStatus = "Checking Squads"
        static let unableToLoadMembershipStatus = "Unable to load Squads"

        static func countSubtitle(count: Int) -> String {
            "\(count) signer\(count == 1 ? "" : "s") · local device"
        }

        static func removeConfirmTitle(label: String) -> String {
            "Remove \"\(label)\""
        }

        static func removeMessage(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                "This removes the signer from this device and deletes its private key from the Keychain. You will need the recovery phrase to add it again."
            case .ledger:
                "This removes the Ledger signer from this device. The Ledger itself is not changed."
            case .yubikey:
                "This removes the YubiKey signer from this device. The YubiKey itself is not changed."
            }
        }

        static func typeName(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                "Hot wallet"
            case .ledger:
                "Ledger"
            case .yubikey:
                "YubiKey"
            }
        }

        static func statusHint(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                "Ready on this device"
            case .ledger:
                "Hardware approval required"
            case .yubikey:
                "Tap or plug in to sign"
            }
        }

        static func keyKind(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                "KEYCHAIN"
            case .ledger:
                "LEDGER"
            case .yubikey:
                "YUBIKEY"
            }
        }

        static func addSignerOptionTitle(for sheet: AddSignerSheet) -> String {
            switch sheet {
            case .hotWallet:
                "Hot Wallet"
            case .ledger:
                "Ledger"
            case .yubikey:
                "YubiKey"
            }
        }

        static func addSignerOptionSubtitle(for sheet: AddSignerSheet) -> String {
            switch sheet {
            case .hotWallet:
                "Create a key stored in iOS Keychain"
            case .ledger:
                "Bluetooth or USB hardware signer"
            case .yubikey:
                "NFC tap or USB security key"
            }
        }

        static func squadCountSubtitle(count: Int) -> String {
            "\(count) squad\(count == 1 ? "" : "s")"
        }

        static func openProposalsTitle(count: Int) -> String {
            "\(count) open proposal\(count == 1 ? "" : "s")"
        }

        static func squadSubtitle(threshold: UInt16, members: UInt32, transactionIndex: UInt64) -> String {
            guard transactionIndex > 0 else {
                return "\(threshold) of \(members) · \(CosignCopy.Squads.noTransactions)"
            }
            return "\(threshold) of \(members) · tx \(transactionIndex)"
        }

        static func pendingApprovalsStatus(count: Int) -> String {
            guard count != 1 else {
                return "1 pending"
            }
            return "\(count) pending approvals"
        }
    }
}

extension CosignCopy {
    enum YubiKeySigning {
        static let pluggedInTransportTitle = "Plugged In"
        static let tapTransportTitle = "Tap"
        static let pluggedInTransportStatus = "plugged-in YubiKey"
        static let nfcTransportStatus = "NFC YubiKey"
        static let sectionTitle = "YubiKey"
        static let pinPlaceholder = "PIN"
        static let pinLengthMessage = "YubiKey PIV PINs must be 6 to 8 characters."
        static let tapPrompt = "Hold your YubiKey near this iPhone to sign."
        static let connectingStatusPrefix = "Connecting to"
        static let signStatus = "Sign with your YubiKey."
        static let checkFailedTitle = "YubiKey check failed"
        static let unsupportedKeyTitle = "Unsupported YubiKey key"
        static let keyNotFoundTitle = "YubiKey key not found"
        static let keyNotReadableTitle = "YubiKey key not readable"

        static func connectingStatus(transport: String) -> String {
            "\(connectingStatusPrefix) \(transport)..."
        }

        static func unsupportedKeyMessage(slotName: String) -> String {
            "The \(slotName) has a key, but it is not Ed25519. " +
                "Provision or import an Ed25519 key in slot 9C with YubiKey Manager, then try again. " +
                "Cosign will not overwrite hardware keys."
        }

        static func keyNotFoundMessage(slotName: String) -> String {
            "Cosign could not find an Ed25519 public key in the \(slotName). " +
                "Provision or import an Ed25519 key in slot 9C with YubiKey Manager, then try again."
        }

        static func keyNotReadableMessage(
            slotName: String,
            metadataError: String,
            certificateError: String
        ) -> String {
            "Cosign could not read an Ed25519 public key from the \(slotName). " +
                "Confirm the PIV app is enabled and slot 9C contains an Ed25519 key. " +
                "Metadata: \(metadataError) Certificate: \(certificateError)"
        }
    }
}
