import Core
import Foundation

extension CosignCopy {
    enum ProposalCreation {
        static let signTransferTitle = String(localized: "Sign Transfer", bundle: .module)
        static let createProposalSubtitle = String(localized: "Create proposal", bundle: .module)
        static let reviewSectionTitle = String(localized: "Review", bundle: .module)
        static let signerSectionTitle = String(localized: "Signer", bundle: .module)
        static let transferSectionTitle = String(localized: "Transfer", bundle: .module)
        static let tokenAccountsSectionTitle = String(localized: "Token Accounts", bundle: .module)
        static let proposalSubmittedTitle = String(localized: "Proposal submitted", bundle: .module)
        static let proposalSubmittedMessage =
            String(
                localized: "Transfer proposal created. It still needs Squad approval before funds can move.",
                bundle: .module
            )
        static let proposalLabel = String(localized: "Proposal", bundle: .module)
        static let statusLabel = String(localized: "Status", bundle: .module)
        static let outcomeLabel = String(localized: "Outcome", bundle: .module)
        static let proposalCreatedOutcome = String(localized: "Create proposal", bundle: .module)
        static let proposalCreatedOutcomeDetail =
            String(localized: "No assets move until the Squad approves and executes this proposal.", bundle: .module)
        static let submittedSignatureTitle = String(localized: "Create proposal", bundle: .module)
        static let signatureSectionTitle = String(localized: "Signature", bundle: .module)
        static let transactionSignatureTitle = String(localized: "Transaction signature", bundle: .module)
        static let addressesSectionTitle = String(localized: "On-chain accounts", bundle: .module)
        static let proposalAccountTitle = String(localized: "Proposal account", bundle: .module)
        static let transactionAccountTitle = String(localized: "Transaction account", bundle: .module)
        static let vaultAddressTitle = String(localized: "Vault address", bundle: .module)
        static let openProposalTitle = String(localized: "Open Proposal", bundle: .module)
        static let signerLabel = String(localized: "Signer", bundle: .module)
        static let signerTypeLabel = String(localized: "Type", bundle: .module)
        static let vaultLabel = String(localized: "Vault", bundle: .module)
        static let signerAddressTitle = String(localized: "Signer address", bundle: .module)
        static let assetLabel = String(localized: "Asset", bundle: .module)
        static let amountLabel = String(localized: "Amount", bundle: .module)
        static let memoLabel = String(localized: "Memo", bundle: .module)
        static let programLabel = String(localized: "Program", bundle: .module)
        static let baseUnitsLabel = String(localized: "Base units", bundle: .module)
        static let mintTitle = String(localized: "Mint", bundle: .module)
        static let sourceTokenAccountTitle = String(localized: "Source token account", bundle: .module)
        static let destinationTokenAccountTitle = String(localized: "Destination token account", bundle: .module)
        static let holdToSign = String(localized: "Hold to sign", bundle: .module)
        static let holdHelpText = String(
            localized: "Hold for 1.5s to prevent accidental proposal creation.",
            bundle: .module
        )
        static let hotWalletSignTitle = String(localized: "Sign", bundle: .module)
        static let recipientTitle = String(localized: "Recipient", bundle: .module)
        static let recipientOwnerTitle = String(localized: "Recipient owner", bundle: .module)
        static let solAssetSymbol = String(localized: "SOL", bundle: .module)
        static let systemProgramTitle = String(localized: "System Program", bundle: .module)
        static let associatedTokenAccountProgramTitle = String(
            localized: "Associated Token Account Program",
            bundle: .module
        )
        static let tokenProgramTitle = String(localized: "Token Program", bundle: .module)
        static let splTokenProgramTitle = String(localized: "SPL Token Program", bundle: .module)
        static let token2022ProgramTitle = String(localized: "Token-2022 Program", bundle: .module)

        static let reviewContext =
            String(
                localized: "You are signing proposal creation. The vault transfer still requires Squad approval and execution.",
                bundle: .module
            )

        static func copyTransactionSignatureAccessibilityLabel() -> String {
            String(localized: "Copy Transaction Signature", bundle: .module)
        }

        static func copyProposalAddressAccessibilityLabel() -> String {
            String(localized: "Copy Proposal Address", bundle: .module)
        }

        static func copyTransactionAddressAccessibilityLabel() -> String {
            String(localized: "Copy Transaction Address", bundle: .module)
        }

        static func copyVaultAddressAccessibilityLabel() -> String {
            String(localized: "Copy Vault Address", bundle: .module)
        }

        static func copySignerAddressAccessibilityLabel() -> String {
            String(localized: "Copy Signer Address", bundle: .module)
        }

        static func copyRecipientAddressAccessibilityLabel() -> String {
            String(localized: "Copy Recipient Address", bundle: .module)
        }

        static func copyMintAddressAccessibilityLabel() -> String {
            String(localized: "Copy Mint Address", bundle: .module)
        }

        static func copySourceTokenAccountAccessibilityLabel() -> String {
            String(localized: "Copy Source Token Account", bundle: .module)
        }

        static func copyDestinationTokenAccountAccessibilityLabel() -> String {
            String(localized: "Copy Destination Token Account", bundle: .module)
        }

        static func transferSummary(amount: String) -> String {
            String(localized: "Transfer \(amount)", bundle: .module)
        }

        static func tokenTransferSummary(amount: String, createsRecipientAccount: Bool) -> String {
            if createsRecipientAccount {
                return String(
                    localized: "\(transferSummary(amount: amount)) and create recipient token account if needed",
                    bundle: .module
                )
            }
            return transferSummary(amount: amount)
        }

        static func createTransferLabel(isTokenTransfer: Bool) -> String {
            isTokenTransfer ? String(localized: "Create token transfer", bundle: .module) : String(
                localized: "Create SOL transfer",
                bundle: .module
            )
        }

        static func createRecipientTokenAccountSummary() -> String {
            String(localized: "Create recipient token account if needed", bundle: .module)
        }

        static func vaultDisplayName(index: UInt8) -> String {
            String(localized: "Vault \(index)", bundle: .module)
        }

        static func signButtonTitle(for signerType: SignerType) -> String {
            switch signerType {
            case .hotWallet:
                hotWalletSignTitle
            case .ledger:
                ProposalSigning.buttonTitle(for: .approve, signerType: .ledger)
            case .yubikey:
                ProposalSigning.buttonTitle(for: .approve, signerType: .yubikey)
            }
        }

        static func hardwareTitle(for signerType: SignerType) -> String {
            switch signerType {
            case .hotWallet:
                ProposalSigning.deviceCheckTitle
            case .ledger:
                ProposalSigning.ledgerTitle
            case .yubikey:
                ProposalSigning.yubiKeyTitle
            }
        }

        static func hardwareContext(for signerType: SignerType) -> String {
            switch signerType {
            case .hotWallet:
                ProposalSigning.deviceContext(for: .hotWallet)
            case .ledger:
                String(
                    localized: "Review the action above before approving on your Ledger. The device may not show full Squads proposal context.",
                    bundle: .module
                )
            case .yubikey:
                String(
                    localized: "Review the action above before tapping your YubiKey. The key signs the proposal transaction; Cosign provides the transfer context.",
                    bundle: .module
                )
            }
        }
    }
}
