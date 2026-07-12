import Core
import Foundation
import Squads

extension CosignCopy {
    enum ProposalSigning {
        static let cancelSigningAccessibilityLabel = String(localized: "Cancel signing", bundle: .module)
        static let highRiskConfirmationTitle = String(localized: "High-risk confirmation", bundle: .module)
        static let proposalLabel = String(localized: "Proposal", bundle: .module)
        static let signerLabel = String(localized: "Signer", bundle: .module)
        static let signingAsLabel = String(localized: "Signing as", bundle: .module)
        static let afterSigningLabel = String(localized: "After this", bundle: .module)
        static let actionOneLabel = String(localized: "Action 1", bundle: .module)
        static let actionTwoLabel = String(localized: "Action 2", bundle: .module)
        static let approvedByLabel = String(localized: "Approved by", bundle: .module)
        static let effectLabel = String(localized: "Effect", bundle: .module)
        static let networkFeeLabel = String(localized: "Network fee", bundle: .module)
        static let approvalActionDetail = String(localized: "Counts as 1 approval", bundle: .module)
        static let executeAfterApprovalDetail = String(localized: "Auto-broadcasts on success", bundle: .module)
        static let networkFeeEstimateDetail = String(localized: "Estimate · paid by the signer", bundle: .module)
        static let networkLabel = String(localized: "Network", bundle: .module)
        static let mainnetSigningDetail = String(localized: "Real funds", bundle: .module)
        static let devnetSigningDetail = String(localized: "Test network", bundle: .module)

        static func priceAsOf(_ date: Date) -> String {
            String(localized: "price as of \(date.formatted(.dateTime.hour().minute()))", bundle: .module)
        }

        static func networkFeeEstimate(lamports: UInt64, solPrice: Double?) -> String {
            let sol = String(localized: "~\(solQuantity(lamports)) SOL", bundle: .module)
            guard let solPrice, solPrice > 0 else {
                return sol
            }
            let usd = (Double(lamports) / 1_000_000_000) * solPrice
            let fiat = usd >= 0.01 ? String(format: "$%.2f", usd) : String(format: "$%.4f", usd)
            return "\(sol) ≈ \(fiat)"
        }

        static let rejectEffectValue = String(localized: "Counts as 1 reject vote", bundle: .module)
        static let cancelEffectValue = String(localized: "Marks proposal cancelled", bundle: .module)
        static let cancelEffectDetail = String(localized: "No further votes are accepted", bundle: .module)
        static let approvedByUnknownValue = String(localized: "Threshold met", bundle: .module)
        static let localHotWalletTitle = String(localized: "Local hot wallet", bundle: .module)
        static let deviceCheckTitle = String(localized: "Device check", bundle: .module)
        static let notBackedUpError = String(localized: "Back up this wallet before it can sign.", bundle: .module)

        static func actionTitle(for action: SquadProposalAction, actionTitle: String) -> String {
            switch action {
            case .approveAndExecute:
                String(localized: "Approve and execute \(lowercasedFirstWord(actionTitle))", bundle: .module)
            case .execute:
                String(localized: "Execute \(lowercasedFirstWord(actionTitle))", bundle: .module)
            case .reject:
                String(localized: "Reject \(lowercasedFirstWord(actionTitle))", bundle: .module)
            case .cancel:
                String(localized: "Cancel \(lowercasedFirstWord(actionTitle))", bundle: .module)
            case .approve:
                actionTitle
            }
        }

        static func actionSubtitle(for action: SquadProposalAction, actionSubtitle: String?) -> String {
            switch action {
            case .approveAndExecute:
                String(localized: "Two transactions broadcast in sequence", bundle: .module)
            case .execute:
                String(localized: "Threshold met · ready to execute", bundle: .module)
            case .reject:
                String(localized: "Records a rejection vote", bundle: .module)
            case .cancel:
                String(localized: "Cancelling is irreversible", bundle: .module)
            case .approve:
                actionSubtitle ?? String(localized: "Records one approval", bundle: .module)
            }
        }

        static func expectationChip(
            for action: SquadProposalAction,
            approvalWouldReachThreshold: Bool
        ) -> String? {
            switch action {
            case .approveAndExecute:
                String(localized: "FINAL SIGNER · WILL EXECUTE", bundle: .module)
            case .approve where approvalWouldReachThreshold:
                String(localized: "FINAL SIGNER · READY TO EXECUTE", bundle: .module)
            case .execute:
                String(localized: "EXECUTES APPROVED TX", bundle: .module)
            case .approve, .reject, .cancel:
                nil
            }
        }

        static func approveProposalTitle(proposalIndex: UInt64?) -> String {
            guard let proposalIndex else {
                return String(localized: "Approve proposal", bundle: .module)
            }
            return String(localized: "Approve proposal #\(proposalIndex)", bundle: .module)
        }

        static func executeActionTitle(actionTitle: String) -> String {
            String(localized: "Execute \(lowercasedFirstWord(actionTitle))", bundle: .module)
        }

        static func approvedByValue(approvals: Int, threshold: Int) -> String {
            String(localized: "\(approvals) of \(threshold) members", bundle: .module)
        }

        static func buttonTitle(for action: SquadProposalAction, signerType: SignerType) -> String {
            switch signerType {
            case .hotWallet:
                hotWalletButtonTitle(for: action)
            }
        }

        static func holdButtonTitle(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                String(localized: "Hold to approve", bundle: .module)
            case .approveAndExecute:
                String(localized: "Hold to approve & execute", bundle: .module)
            case .reject:
                String(localized: "Hold to reject", bundle: .module)
            case .cancel:
                String(localized: "Hold to cancel", bundle: .module)
            case .execute:
                String(localized: "Hold to execute", bundle: .module)
            }
        }

        static func holdHelpText(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                String(localized: "Hold for 1.5s to prevent accidental approvals.", bundle: .module)
            case .approveAndExecute:
                String(localized: "Hold for 1.5s to prevent accidental approval and execution.", bundle: .module)
            case .execute:
                String(localized: "Hold for 1.5s to prevent accidental execution.", bundle: .module)
            case .reject:
                String(localized: "Hold for 1.5s to prevent accidental rejection.", bundle: .module)
            case .cancel:
                String(localized: "Hold for 1.5s to prevent accidental cancellation.", bundle: .module)
            }
        }

        static func afterSigningText(
            for action: SquadProposalAction,
            approvalWouldReachThreshold: Bool
        ) -> String {
            switch action {
            case .approveAndExecute:
                String(localized: "Approve, then execute", bundle: .module)
            case .approve:
                if approvalWouldReachThreshold {
                    String(localized: "Ready to execute", bundle: .module)
                } else {
                    String(localized: "Approval recorded", bundle: .module)
                }
            case .reject:
                String(localized: "Rejection recorded", bundle: .module)
            case .cancel:
                String(localized: "Cancellation recorded", bundle: .module)
            case .execute:
                String(localized: "Transaction executed", bundle: .module)
            }
        }

        static func highRiskConfirmationPrompt(_ phrase: String) -> String {
            String(localized: "Type \(phrase) to enable signing.", bundle: .module)
        }

        static func highRiskConfirmationPhrase(proposalIndex: UInt64?) -> String {
            "PROPOSAL \(proposalIndex ?? 0)"
        }

        static func fallbackSubtitle(for action: SquadProposalAction) -> String {
            switch action {
            case .approveAndExecute:
                String(localized: "Approve, then execute", bundle: .module)
            case .approve, .execute, .reject, .cancel:
                String(localized: "Squads proposal action", bundle: .module)
            }
        }

        static var deviceContext: String {
            String(localized: "The private key stays in the device Keychain.", bundle: .module)
        }

        private static func hotWalletButtonTitle(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                String(localized: "Approve", bundle: .module)
            case .approveAndExecute:
                String(localized: "Approve & Execute", bundle: .module)
            case .execute:
                String(localized: "Execute", bundle: .module)
            case .reject:
                String(localized: "Reject", bundle: .module)
            case .cancel:
                String(localized: "Cancel proposal", bundle: .module)
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
    enum BroadcastError {
        static let maxAttempts = 3

        static let retryableTitle = String(localized: "Couldn't broadcast", bundle: .module)
        static let terminalTitle = String(localized: "Still can't reach the network", bundle: .module)

        static let signatureSafeLine = String(
            localized: "Your signature is saved on this device. It is not lost.",
            bundle: .module
        )
        static let idempotencyCaption =
            String(
                localized: "Retrying re-sends the same signed transaction. Safe to retry, the network ignores duplicates.",
                bundle: .module
            )
        static let reasonLabel = String(localized: "Reason", bundle: .module)

        static let retryPrimary = String(localized: "Retry broadcast", bundle: .module)
        static let retrySecondary = String(localized: "Dismiss", bundle: .module)
        static let terminalPrimary = String(localized: "Done", bundle: .module)
        static let terminalSecondary = String(localized: "Try broadcast again", bundle: .module)

        static func reasonValue(reason: String, attempt: Int) -> String {
            String(localized: "\(reason) \u{00B7} attempt \(attempt) of \(maxAttempts)", bundle: .module)
        }
    }
}
