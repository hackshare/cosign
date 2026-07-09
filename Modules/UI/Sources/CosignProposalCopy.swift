import Core
import Foundation
import Squads

extension CosignCopy {
    enum ProposalSigning {
        static let cancelSigningAccessibilityLabel = "Cancel signing"
        static let highRiskConfirmationTitle = "High-risk confirmation"
        static let proposalLabel = "Proposal"
        static let signerLabel = "Signer"
        static let signingAsLabel = "Signing as"
        static let afterSigningLabel = "After this"
        static let actionOneLabel = "Action 1"
        static let actionTwoLabel = "Action 2"
        static let approvedByLabel = "Approved by"
        static let effectLabel = "Effect"
        static let networkFeeLabel = "Network fee"
        static let approvalActionDetail = "Counts as 1 approval"
        static let executeAfterApprovalDetail = "Auto-broadcasts on success"
        static let networkFeeEstimateDetail = "Estimate · paid by the signer"

        static func networkFeeEstimate(lamports: UInt64, solPrice: Double?) -> String {
            let sol = "~\(solQuantity(lamports)) SOL"
            guard let solPrice, solPrice > 0 else {
                return sol
            }
            let usd = (Double(lamports) / 1_000_000_000) * solPrice
            let fiat = usd >= 0.01 ? String(format: "$%.2f", usd) : String(format: "$%.4f", usd)
            return "\(sol) ≈ \(fiat)"
        }

        static let rejectEffectValue = "Counts as 1 reject vote"
        static let cancelEffectValue = "Marks proposal cancelled"
        static let cancelEffectDetail = "No further votes are accepted"
        static let approvedByUnknownValue = "Threshold met"
        static let localHotWalletTitle = "Local hot wallet"
        static let deviceCheckTitle = "Device check"
        static let ledgerTitle = "Ledger"
        static let yubiKeyTitle = "YubiKey"
        static let scanningLedgerStatus = "Scanning for Ledger devices..."
        static let verifyingLedgerAddressStatus = "Verifying Ledger address..."
        static let confirmLedgerStatus = "Confirm the transaction on your Ledger."
        static let noLedgerDevicesError = "No Ledger devices were found."
        static let missingYubiKeyOptionsError = "YubiKey signing needs a connection choice and PIN."
        static let notBackedUpError = "Back up this wallet before it can sign."

        static func connectingLedgerStatus(deviceName: String) -> String {
            "Connecting to \(deviceName)..."
        }

        static func actionTitle(for action: SquadProposalAction, actionTitle: String) -> String {
            switch action {
            case .approveAndExecute:
                "Approve and execute \(lowercasedFirstWord(actionTitle))"
            case .execute:
                "Execute \(lowercasedFirstWord(actionTitle))"
            case .reject:
                "Reject \(lowercasedFirstWord(actionTitle))"
            case .cancel:
                "Cancel \(lowercasedFirstWord(actionTitle))"
            case .approve:
                actionTitle
            }
        }

        static func actionSubtitle(for action: SquadProposalAction, actionSubtitle: String?) -> String {
            switch action {
            case .approveAndExecute:
                "Two transactions broadcast in sequence"
            case .execute:
                "Threshold met · ready to execute"
            case .reject:
                "Records a rejection vote"
            case .cancel:
                "Cancelling is irreversible"
            case .approve:
                actionSubtitle ?? "Records one approval"
            }
        }

        static func expectationChip(
            for action: SquadProposalAction,
            approvalWouldReachThreshold: Bool
        ) -> String? {
            switch action {
            case .approveAndExecute:
                "FINAL SIGNER · WILL EXECUTE"
            case .approve where approvalWouldReachThreshold:
                "FINAL SIGNER · READY TO EXECUTE"
            case .execute:
                "EXECUTES APPROVED TX"
            case .approve, .reject, .cancel:
                nil
            }
        }

        static func approveProposalTitle(proposalIndex: UInt64?) -> String {
            guard let proposalIndex else {
                return "Approve proposal"
            }
            return "Approve proposal #\(proposalIndex)"
        }

        static func executeActionTitle(actionTitle: String) -> String {
            "Execute \(lowercasedFirstWord(actionTitle))"
        }

        static func approvedByValue(approvals: Int, threshold: Int) -> String {
            "\(approvals) of \(threshold) members"
        }

        static func buttonTitle(for action: SquadProposalAction, signerType: SignerType) -> String {
            switch signerType {
            case .hotWallet:
                hotWalletButtonTitle(for: action)
            case .ledger:
                "Continue on Ledger"
            case .yubikey:
                "Sign with YubiKey"
            }
        }

        static func holdButtonTitle(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                "Hold to approve"
            case .approveAndExecute:
                "Hold to approve & execute"
            case .reject:
                "Hold to reject"
            case .cancel:
                "Hold to cancel"
            case .execute:
                "Hold to execute"
            }
        }

        static func holdHelpText(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                "Hold for 1.5s to prevent accidental approvals."
            case .approveAndExecute:
                "Hold for 1.5s to prevent accidental approval and execution."
            case .execute:
                "Hold for 1.5s to prevent accidental execution."
            case .reject:
                "Hold for 1.5s to prevent accidental rejection."
            case .cancel:
                "Hold for 1.5s to prevent accidental cancellation."
            }
        }

        static func afterSigningText(
            for action: SquadProposalAction,
            approvalWouldReachThreshold: Bool
        ) -> String {
            switch action {
            case .approveAndExecute:
                "Approve, then execute"
            case .approve:
                approvalWouldReachThreshold ? "Ready to execute" : "Approval recorded"
            case .reject:
                "Rejection recorded"
            case .cancel:
                "Cancellation recorded"
            case .execute:
                "Transaction executed"
            }
        }

        static func highRiskConfirmationPrompt(_ phrase: String) -> String {
            "Type \(phrase) to enable signing."
        }

        static func highRiskConfirmationPhrase(proposalIndex: UInt64?) -> String {
            "PROPOSAL \(proposalIndex ?? 0)"
        }

        static func fallbackSubtitle(for action: SquadProposalAction) -> String {
            switch action {
            case .approveAndExecute:
                "Approve, then execute"
            case .approve, .execute, .reject, .cancel:
                "Squads proposal action"
            }
        }

        static func deviceContext(for signerType: SignerType) -> String {
            switch signerType {
            case .hotWallet:
                "The private key stays in the device Keychain."
            case .ledger:
                "Review the action above before approving on your Ledger. The device may not show full Squads proposal context."
            case .yubikey:
                "Review the action above before tapping your YubiKey. The key signs the transaction message; Cosign provides the proposal context."
            }
        }

        private static func hotWalletButtonTitle(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                "Approve"
            case .approveAndExecute:
                "Approve & Execute"
            case .execute:
                "Execute"
            case .reject:
                "Reject"
            case .cancel:
                "Cancel proposal"
            }
        }

        private static func lowercasedFirstWord(_ value: String) -> String {
            guard let first = value.first else {
                return value
            }

            return first.lowercased() + value.dropFirst()
        }
    }
}

extension CosignCopy {
    enum ProposalCreation {
        static let signTransferTitle = "Sign Transfer"
        static let createProposalSubtitle = "Create proposal"
        static let reviewSectionTitle = "Review"
        static let signerSectionTitle = "Signer"
        static let transferSectionTitle = "Transfer"
        static let tokenAccountsSectionTitle = "Token Accounts"
        static let proposalSubmittedTitle = "Proposal submitted"
        static let proposalSubmittedMessage =
            "Transfer proposal created. It still needs Squad approval before funds can move."
        static let proposalLabel = "Proposal"
        static let statusLabel = "Status"
        static let outcomeLabel = "Outcome"
        static let proposalCreatedOutcome = "Create proposal"
        static let proposalCreatedOutcomeDetail =
            "No assets move until the Squad approves and executes this proposal."
        static let submittedSignatureTitle = "Create proposal"
        static let signatureSectionTitle = "Signature"
        static let transactionSignatureTitle = "Transaction signature"
        static let addressesSectionTitle = "On-chain accounts"
        static let proposalAccountTitle = "Proposal account"
        static let transactionAccountTitle = "Transaction account"
        static let vaultAddressTitle = "Vault address"
        static let openProposalTitle = "Open Proposal"
        static let signerLabel = "Signer"
        static let signerTypeLabel = "Type"
        static let vaultLabel = "Vault"
        static let signerAddressTitle = "Signer address"
        static let assetLabel = "Asset"
        static let amountLabel = "Amount"
        static let memoLabel = "Memo"
        static let programLabel = "Program"
        static let baseUnitsLabel = "Base units"
        static let mintTitle = "Mint"
        static let sourceTokenAccountTitle = "Source token account"
        static let destinationTokenAccountTitle = "Destination token account"
        static let holdToSign = "Hold to sign"
        static let holdHelpText = "Hold for 1.5s to prevent accidental proposal creation."
        static let hotWalletSignTitle = "Sign"
        static let recipientTitle = "Recipient"
        static let recipientOwnerTitle = "Recipient owner"
        static let solAssetSymbol = "SOL"
        static let systemProgramTitle = "System Program"
        static let associatedTokenAccountProgramTitle = "Associated Token Account Program"
        static let tokenProgramTitle = "Token Program"
        static let splTokenProgramTitle = "SPL Token Program"
        static let token2022ProgramTitle = "Token-2022 Program"

        static let reviewContext =
            "You are signing proposal creation. The vault transfer still requires Squad approval and execution."

        static func copyTransactionSignatureAccessibilityLabel() -> String {
            "Copy Transaction Signature"
        }

        static func copyProposalAddressAccessibilityLabel() -> String {
            "Copy Proposal Address"
        }

        static func copyTransactionAddressAccessibilityLabel() -> String {
            "Copy Transaction Address"
        }

        static func copyVaultAddressAccessibilityLabel() -> String {
            "Copy Vault Address"
        }

        static func copySignerAddressAccessibilityLabel() -> String {
            "Copy Signer Address"
        }

        static func copyRecipientAddressAccessibilityLabel() -> String {
            "Copy Recipient Address"
        }

        static func copyMintAddressAccessibilityLabel() -> String {
            "Copy Mint Address"
        }

        static func copySourceTokenAccountAccessibilityLabel() -> String {
            "Copy Source Token Account"
        }

        static func copyDestinationTokenAccountAccessibilityLabel() -> String {
            "Copy Destination Token Account"
        }

        static func transferSummary(amount: String) -> String {
            "Transfer \(amount)"
        }

        static func tokenTransferSummary(amount: String, createsRecipientAccount: Bool) -> String {
            if createsRecipientAccount {
                return "\(transferSummary(amount: amount)) and create recipient token account if needed"
            }
            return transferSummary(amount: amount)
        }

        static func createTransferLabel(isTokenTransfer: Bool) -> String {
            isTokenTransfer ? "Create token transfer" : "Create SOL transfer"
        }

        static func createRecipientTokenAccountSummary() -> String {
            "Create recipient token account if needed"
        }

        static func vaultDisplayName(index: UInt8) -> String {
            "Vault \(index)"
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
                "Review the action above before approving on your Ledger. The device may not show full Squads proposal context."
            case .yubikey:
                "Review the action above before tapping your YubiKey. The key signs the proposal transaction; Cosign provides the transfer context."
            }
        }
    }
}

extension CosignCopy {
    enum BroadcastError {
        static let maxAttempts = 3

        static let retryableTitle = "Couldn't broadcast"
        static let terminalTitle = "Still can't reach the network"

        static let signatureSafeLine = "Your signature is saved on this device. It is not lost."
        static let idempotencyCaption =
            "Retrying re-sends the same signed transaction. Safe to retry, the network ignores duplicates."
        static let reasonLabel = "Reason"

        static let retryPrimary = "Retry broadcast"
        static let retrySecondary = "Dismiss"
        static let terminalPrimary = "Done"
        static let terminalSecondary = "Try broadcast again"

        static func reasonValue(reason: String, attempt: Int) -> String {
            "\(reason) \u{00B7} attempt \(attempt) of \(maxAttempts)"
        }
    }
}
