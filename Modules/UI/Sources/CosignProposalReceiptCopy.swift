import Squads

extension CosignCopy {
    enum ProposalReceipt {
        static let outcomeLabel = "Outcome"
        static let statusLabel = "Status"
        static let slotLabel = "Slot"
        static let feeLabel = "Fee"
        static let blockTimeLabel = "Block time"
        static let confirmationLabel = "Confirmation"

        static func feeValue(lamports: UInt64) -> String {
            "\(solQuantity(lamports)) SOL"
        }

        static let factsTitle = "What happened"
        static let confirmedBadge = "CONFIRMED"
        static let viewProposal = "View proposal"
        static let broadcastLabel = "Broadcast"
        static let signaturesTitle = "Signatures"
        static let signatureLabel = "Signature"

        static func title(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                "Approved & broadcast"
            case .approveAndExecute:
                "Approved & executed"
            case .execute:
                "Executed"
            case .reject:
                "Reject recorded"
            case .cancel:
                "Proposal cancelled"
            }
        }

        static func outcome(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                "Approve"
            case .approveAndExecute:
                "Approve and execute"
            case .execute:
                "Execute"
            case .reject:
                "Reject"
            case .cancel:
                "Cancel"
            }
        }

        static func subtitle(
            for action: SquadProposalAction,
            status: String,
            broadcastCount: Int,
            proposalIndex: UInt64?
        ) -> String {
            let proposal = proposalIndex.map { "Proposal #\($0) · " } ?? ""
            return switch action {
            case .approve:
                "\(proposal)status \(displayLabel(status)) · \(broadcastValue(broadcastCount))"
            case .approveAndExecute:
                "\(proposal)threshold met · \(broadcastValue(broadcastCount))"
            case .execute:
                "\(proposal)status \(displayLabel(status)) · \(broadcastValue(broadcastCount))"
            case .reject:
                "\(proposal)reject vote broadcast · status \(displayLabel(status))"
            case .cancel:
                "\(proposal)status \(displayLabel(status)) · no further votes accepted"
            }
        }

        static func copyAccessibilityLabel(for label: String) -> String {
            "Copy \(label) Signature"
        }

        static func broadcastValue(_ count: Int) -> String {
            "\(count) \(count == 1 ? "transaction" : "transactions")"
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
                "Approval recorded; execution is separate unless threshold rules already ran it."
            case .approveAndExecute:
                "Approval was sent first, followed by execution."
            case .execute:
                "The approved transaction was sent on chain."
            case .reject:
                "No assets move; this records a rejection vote."
            case .cancel:
                "The proposal is closed to further voting."
            }
        }
    }
}
