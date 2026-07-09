import Foundation

extension CosignCopy {
    enum HotWallet {
        static let defaultLabel = String(localized: "My Wallet", bundle: .module)
        static let errorTitle = String(localized: "Hot Wallet Error", bundle: .module)
        static let newWalletTitle = String(localized: "New Hot Wallet", bundle: .module)
        static let walletSectionTitle = String(localized: "Hot wallet", bundle: .module)
        static let createTitle = String(localized: "Create Signer", bundle: .module)
        static let labelSectionTitle = String(localized: "Label", bundle: .module)
        static let generateMnemonicTitle = String(localized: "Generate Mnemonic", bundle: .module)
        static let createSegment = String(localized: "Create", bundle: .module)
        static let importSegment = String(localized: "Import", bundle: .module)
        static let createInfoNote =
            String(
                localized: "A new 24-word recovery phrase is generated on-device. You'll be asked to back it up before it can sign.",
                bundle: .module
            )
        static let importTitle = String(localized: "Import Wallet", bundle: .module)
        static let importHeadline = String(localized: "Import Signer", bundle: .module)
        static let recoveryPhraseSectionTitle = String(localized: "Recovery phrase", bundle: .module)
        static let pastePhraseTitle = String(localized: "Paste phrase", bundle: .module)
        static let pastePhraseAccessibilityLabel = String(localized: "Paste recovery phrase", bundle: .module)
        static let keychainNote =
            String(
                localized: "Stored in the iOS Keychain · never leaves this device · clipboard cleared after paste.",
                bundle: .module
            )
        static let importValidationHint = String(localized: "Import enabled once every word is valid.", bundle: .module)
        static let wordCountSeparator = String(localized: "·", bundle: .module)

        // Secret-key import mode
        static let secretKeySectionTitle = String(localized: "Secret key", bundle: .module)
        static let secretKeyModeLabel = String(localized: "[…]", bundle: .module)
        static let secretKeyPlaceholder = String(localized: "[ paste your keypair.json array ]", bundle: .module)
        static let secretKeyNeverShown =
            String(
                localized: "Full key is never shown on screen — only the derived address is echoed back.",
                bundle: .module
            )
        static let pasteSecretKeyTitle = String(localized: "Paste from clipboard", bundle: .module)
        static let secretKeyNotArray = String(
            localized: "Not a number array — expects [12, 34, …] from keypair.json",
            bundle: .module
        )
        static let secretKeyInvalid = String(
            localized: "Invalid key — bytes are not a valid ed25519 keypair",
            bundle: .module
        )
        static let secretKeyCaution =
            String(
                localized: "A raw secret key is the whole wallet — anyone with it controls the funds. Pasted into the Keychain, then the clipboard is cleared.",
                bundle: .module
            )
        static let secretKeyValidationHint = String(
            localized: "Import enabled once a valid 64-byte key is pasted.",
            bundle: .module
        )

        static func secretKeyValid(address: String) -> String {
            let short = address.count > 8 ? "\(address.prefix(4))…\(address.suffix(4))" : address
            return String(localized: "64 bytes · valid key → \(short)", bundle: .module)
        }

        static func secretKeyWrongLength(got: Int) -> String {
            String(localized: "Wrong length — need 64 bytes (32 secret + 32 public) · got \(got)", bundle: .module)
        }

        static let importButtonTitle = String(localized: "Import Wallet", bundle: .module)
        static let backupTitle = String(localized: "Backup Mnemonic", bundle: .module)
        static let backupSectionTitle = String(localized: "Backup", bundle: .module)
        static let mnemonicTitle = String(localized: "Mnemonic", bundle: .module)
        static let backupMessage =
            String(
                localized: "Write these 24 words down in order. They are your only way to recover this wallet.",
                bundle: .module
            )
        static let writtenDownTitle = String(localized: "I've Written It Down", bundle: .module)
        static let walletAddedTitle = String(localized: "Wallet Added", bundle: .module)
        static let walletAddedMessage = String(localized: "This signer is stored on this device.", bundle: .module)
        static let memberAddressTitle = String(localized: "Member address", bundle: .module)
        static let copyMemberAddress = String(localized: "Copy Member Address", bundle: .module)
        static let doneButtonTitle = String(localized: "Done", bundle: .module)

        static func saveFailedMessage(_ error: any Error) -> String {
            String(localized: "Failed to save signer: \(String(describing: error))", bundle: .module)
        }

        static func wordOrdinal(_ index: Int) -> String {
            String(localized: "\(index).", bundle: .module)
        }

        static func wordIndexLabel(_ index: Int) -> String {
            "\(index)"
        }

        static func wordCountLabel(_ count: Int) -> String {
            "\(count)"
        }

        static func validWordCountLabel(valid: Int, total: Int) -> String {
            String(localized: "\(valid) / \(total)", bundle: .module)
        }
    }
}
