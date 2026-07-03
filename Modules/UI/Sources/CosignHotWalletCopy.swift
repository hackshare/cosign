extension CosignCopy {
    enum HotWallet {
        static let defaultLabel = "My Wallet"
        static let errorTitle = "Hot Wallet Error"
        static let newWalletTitle = "New Hot Wallet"
        static let walletSectionTitle = "Hot wallet"
        static let createTitle = "Create Signer"
        static let labelSectionTitle = "Label"
        static let generateMnemonicTitle = "Generate Mnemonic"
        static let createSegment = "Create"
        static let importSegment = "Import"
        static let createInfoNote =
            "A new 24-word recovery phrase is generated on-device. " +
            "You'll be asked to back it up before it can sign."
        static let importTitle = "Import Wallet"
        static let importHeadline = "Import Signer"
        static let recoveryPhraseSectionTitle = "Recovery phrase"
        static let pastePhraseTitle = "Paste phrase"
        static let pastePhraseAccessibilityLabel = "Paste recovery phrase"
        static let keychainNote =
            "Stored in the iOS Keychain · never leaves this device · clipboard cleared after paste."
        static let importValidationHint = "Import enabled once every word is valid."
        static let wordCountSeparator = "·"

        // Secret-key import mode
        static let secretKeySectionTitle = "Secret key"
        static let secretKeyModeLabel = "[…]"
        static let secretKeyPlaceholder = "[ paste your keypair.json array ]"
        static let secretKeyNeverShown =
            "Full key is never shown on screen — only the derived address is echoed back."
        static let pasteSecretKeyTitle = "Paste from clipboard"
        static let secretKeyNotArray = "Not a number array — expects [12, 34, …] from keypair.json"
        static let secretKeyInvalid = "Invalid key — bytes are not a valid ed25519 keypair"
        static let secretKeyCaution =
            "A raw secret key is the whole wallet — anyone with it controls the funds. " +
            "Pasted into the Keychain, then the clipboard is cleared."
        static let secretKeyValidationHint = "Import enabled once a valid 64-byte key is pasted."

        static func secretKeyValid(address: String) -> String {
            let short = address.count > 8 ? "\(address.prefix(4))…\(address.suffix(4))" : address
            return "64 bytes · valid key → \(short)"
        }

        static func secretKeyWrongLength(got: Int) -> String {
            "Wrong length — need 64 bytes (32 secret + 32 public) · got \(got)"
        }

        static let importButtonTitle = "Import Wallet"
        static let backupTitle = "Backup Mnemonic"
        static let backupSectionTitle = "Backup"
        static let mnemonicTitle = "Mnemonic"
        static let backupMessage =
            "Write these 24 words down in order. They are your only way to recover this wallet."
        static let writtenDownTitle = "I've Written It Down"
        static let walletAddedTitle = "Wallet Added"
        static let walletAddedMessage = "This signer is stored on this device."
        static let memberAddressTitle = "Member address"
        static let copyMemberAddress = "Copy Member Address"
        static let doneButtonTitle = "Done"

        static func saveFailedMessage(_ error: any Error) -> String {
            "Failed to save signer: \(error)"
        }

        static func wordOrdinal(_ index: Int) -> String {
            "\(index)."
        }

        static func wordIndexLabel(_ index: Int) -> String {
            "\(index)"
        }

        static func wordCountLabel(_ count: Int) -> String {
            "\(count)"
        }

        static func validWordCountLabel(valid: Int, total: Int) -> String {
            "\(valid) / \(total)"
        }
    }
}
