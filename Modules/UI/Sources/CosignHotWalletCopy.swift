import Core

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
