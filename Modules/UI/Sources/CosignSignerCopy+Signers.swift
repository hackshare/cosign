import Core
import Foundation

extension CosignCopy {
    enum Signers {
        static let settingsAccessibilityLabel = String(localized: "Settings", bundle: .module)
        static let title = String(localized: "Signers", bundle: .module)
        static let searchPlaceholder = String(localized: "Search signers", bundle: .module)
        static let removeSignerMenuTitle = String(localized: "Remove Signer", bundle: .module)
        static let removeSignerTitle = String(localized: "Remove signer?", bundle: .module)
        static let keepSignerTitle = String(localized: "Keep Signer", bundle: .module)
        static let connectOrCreateTitle = String(localized: "Connect or create signer", bundle: .module)
        static let copySignerAddress = String(localized: "Copy Signer Address", bundle: .module)
        static let addSignerTitle = String(localized: "Add signer", bundle: .module)
        static let addSignerSubtitle = String(
            localized: "Choose the key you want to use for approvals.",
            bundle: .module
        )
        static let closeAccessibilityLabel = String(localized: "Close", bundle: .module)
        static let signerNotFoundTitle = String(localized: "Signer Not Found", bundle: .module)
        static let signerNotFoundMessage = String(
            localized: "This signer is no longer on this device.",
            bundle: .module
        )
        static let signerSettingsAccessibilityLabel = String(localized: "Signer Settings", bundle: .module)
        static let pendingSquadsSubtitle = String(localized: "Across this signer's Squads", bundle: .module)
        static let unableToLoadSquadsTitle = String(localized: "Unable to Load Squads", bundle: .module)
        static let recentSectionTitle = String(localized: "Recent", bundle: .module)
        static let allClear = String(localized: "All clear", bundle: .module)
        static let loadingMembershipStatus = String(localized: "Checking Squads", bundle: .module)
        static let unableToLoadMembershipStatus = String(localized: "Unable to load Squads", bundle: .module)

        static func countSubtitle(count: Int) -> String {
            String(localized: "\(count) signer\(count == 1 ? "" : "s") · local device", bundle: .module)
        }

        static func removeConfirmTitle(label: String) -> String {
            String(localized: "Remove \"\(label)\"", bundle: .module)
        }

        static func removeSquadMembershipNote(count: Int) -> String {
            count == 1
                ? String(
                    localized: "This signer is a member of 1 Squad. Removing it here does not change the Squad on-chain; you can re-add the signer later.",
                    bundle: .module
                )
                : String(
                    localized: "This signer is a member of \(count) Squads. Removing it here does not change those Squads on-chain; you can re-add the signer later.",
                    bundle: .module
                )
        }

        static let comingSoonTag = String(localized: "Coming soon", bundle: .module)
        static let ledgerComingSoonTitle = String(localized: "Ledger", bundle: .module)
        static let ledgerComingSoonSubtitle = String(localized: "Bluetooth or USB hardware signer", bundle: .module)
        static let yubiKeyComingSoonTitle = String(localized: "YubiKey", bundle: .module)
        static let yubiKeyComingSoonSubtitle = String(localized: "NFC tap or USB security key", bundle: .module)

        static func removeMessage(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                String(
                    localized: "This removes the signer from this device and deletes its private key from the Keychain. You will need the recovery phrase to add it again.",
                    bundle: .module
                )
            }
        }

        static func typeName(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                String(localized: "Hot wallet", bundle: .module)
            }
        }

        static func statusHint(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                String(localized: "Ready on this device", bundle: .module)
            }
        }

        static func keyKind(for type: SignerType) -> String {
            switch type {
            case .hotWallet:
                String(localized: "KEYCHAIN", bundle: .module)
            }
        }

        static func addSignerOptionTitle(for sheet: AddSignerSheet) -> String {
            switch sheet {
            case .hotWallet:
                String(localized: "Hot Wallet", bundle: .module)
            }
        }

        static func addSignerOptionSubtitle(for sheet: AddSignerSheet) -> String {
            switch sheet {
            case .hotWallet:
                String(localized: "Create a key stored in iOS Keychain", bundle: .module)
            }
        }

        static func squadCountSubtitle(count: Int) -> String {
            String(localized: "\(count) squad\(count == 1 ? "" : "s")", bundle: .module)
        }

        static func openProposalsTitle(count: Int) -> String {
            String(localized: "\(count) open proposal\(count == 1 ? "" : "s")", bundle: .module)
        }

        static func squadSubtitle(threshold: UInt16, members: UInt32, transactionIndex: UInt64) -> String {
            guard transactionIndex > 0 else {
                return String(
                    localized: "\(threshold) of \(members) · \(CosignCopy.Squads.noTransactions)",
                    bundle: .module
                )
            }
            return String(localized: "\(threshold) of \(members) · tx \(transactionIndex)", bundle: .module)
        }

        static func pendingApprovalsStatus(count: Int) -> String {
            guard count != 1 else {
                return String(localized: "1 pending", bundle: .module)
            }
            return String(localized: "\(count) pending approvals", bundle: .module)
        }
    }
}
