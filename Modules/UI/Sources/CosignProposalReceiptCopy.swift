import Foundation
import Squads

extension CosignCopy {
    enum ProposalReceipt {
        static let outcomeLabel = String(localized: "Outcome", bundle: .module)
        static let statusLabel = String(localized: "Status", bundle: .module)
        static let slotLabel = String(localized: "Slot", bundle: .module)
        static let feeLabel = String(localized: "Fee", bundle: .module)
        static let blockTimeLabel = String(localized: "Block time", bundle: .module)
        static let confirmationLabel = String(localized: "Confirmation", bundle: .module)

        static func feeValue(lamports: UInt64) -> String {
            String(localized: "\(solQuantity(lamports)) SOL", bundle: .module)
        }

        static let factsTitle = String(localized: "What happened", bundle: .module)
        static let confirmedBadge = String(localized: "CONFIRMED", bundle: .module)
        static let viewProposal = String(localized: "View proposal", bundle: .module)
        static let broadcastLabel = String(localized: "Broadcast", bundle: .module)
        static let signaturesTitle = String(localized: "Signatures", bundle: .module)
        static let signatureLabel = String(localized: "Signature", bundle: .module)

        static func title(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                String(localized: "Approved & broadcast", bundle: .module)
            case .approveAndExecute:
                String(localized: "Approved & executed", bundle: .module)
            case .execute:
                String(localized: "Executed", bundle: .module)
            case .reject:
                String(localized: "Reject recorded", bundle: .module)
            case .cancel:
                String(localized: "Proposal cancelled", bundle: .module)
            }
        }

        static func outcome(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                String(localized: "Approve", bundle: .module)
            case .approveAndExecute:
                String(localized: "Approve and execute", bundle: .module)
            case .execute:
                String(localized: "Execute", bundle: .module)
            case .reject:
                String(localized: "Reject", bundle: .module)
            case .cancel:
                String(localized: "Cancel", bundle: .module)
            }
        }

        static func subtitle(
            for action: SquadProposalAction,
            status: String,
            broadcastCount: Int,
            proposalIndex: UInt64?
        ) -> String {
            let proposal = proposalIndex.map { String(localized: "Proposal #\($0) · ", bundle: .module) } ?? ""
            return switch action {
            case .approve:
                String(
                    localized: "\(proposal)status \(displayLabel(status)) · \(broadcastValue(broadcastCount))",
                    bundle: .module
                )
            case .approveAndExecute:
                String(localized: "\(proposal)threshold met · \(broadcastValue(broadcastCount))", bundle: .module)
            case .execute:
                String(
                    localized: "\(proposal)status \(displayLabel(status)) · \(broadcastValue(broadcastCount))",
                    bundle: .module
                )
            case .reject:
                String(localized: "\(proposal)reject vote broadcast · status \(displayLabel(status))", bundle: .module)
            case .cancel:
                String(
                    localized: "\(proposal)status \(displayLabel(status)) · no further votes accepted",
                    bundle: .module
                )
            }
        }

        static func copyAccessibilityLabel(for label: String) -> String {
            "Copy \(label) Signature"
        }

        static func broadcastValue(_ count: Int) -> String {
            String(localized: "\(count) \(count == 1 ? "transaction" : "transactions")", bundle: .module)
        }

        static func broadcastDetail(for signatures: [ProposalSubmissionSignature]) -> String? {
            let labels = signatures.map { $0.label.lowercased() }
            guard labels.count > 1 else {
                return labels.first
            }
            return labels.joined(separator: " · ")
        }

        static func outcomeDetail(for action: SquadProposalAction) -> String? {
            switch action {
            case .approve:
                String(
                    localized: "Approval recorded; execution is separate unless threshold rules already ran it.",
                    bundle: .module
                )
            case .approveAndExecute:
                String(localized: "Approval was sent first, followed by execution.", bundle: .module)
            case .execute:
                String(localized: "The approved transaction was sent on chain.", bundle: .module)
            case .reject:
                String(localized: "No assets move; this records a rejection vote.", bundle: .module)
            case .cancel:
                String(localized: "The proposal is closed to further voting.", bundle: .module)
            }
        }

        static let partialTitle = String(localized: "Approval recorded", bundle: .module)
        static let partialSubtitle = String(
            localized: "Your approval landed and is counted toward the threshold. Execution did not broadcast, so the transfer has not run yet. You can execute it later.",
            bundle: .module
        )
        static let partialActionSectionTitle = String(localized: "This action", bundle: .module)
        static let partialStepApprove = String(localized: "Approve", bundle: .module)
        static let partialStepExecute = String(localized: "Execute", bundle: .module)
        static let partialApproveDone = String(localized: "Done", bundle: .module)
        static let partialExecutePending = String(localized: "Pending", bundle: .module)
        static let partialExecuteDetail = String(localized: "Not broadcast \u{00B7} ready to run", bundle: .module)
        static let partialFinishExecution = String(localized: "Finish execution", bundle: .module)
    }
}
