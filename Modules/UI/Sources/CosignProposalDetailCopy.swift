import Foundation
import Squads

extension CosignCopy {
    enum ProposalDetail {
        static func proposedBy(_ proposer: String, createdAtUnix: Int64?) -> String {
            let who = cosignShortAddress(proposer)
            guard let createdAtUnix else {
                return "Proposed by \(who)"
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let when = formatter.localizedString(
                for: Date(timeIntervalSince1970: TimeInterval(createdAtUnix)),
                relativeTo: Date()
            )
            return "Proposed by \(who) · \(when)"
        }

        static let unableToLoadTitle = "Unable to Load Proposal"
        static let retryButtonTitle = "Retry"
        static let decodedFieldsSectionTitle = "Decoded fields"
        static let technicalDetailsSectionTitle = "Technical details"
        static let votesSectionTitle = "Votes"
        static let approvalsSectionTitle = "Approvals"
        static let rejectionsSectionTitle = "Rejections"
        static let cancellationsSectionTitle = "Cancellations"
        static let approveVoteTitle = "Approve"
        static let rejectVoteTitle = "Reject"
        static let cancelVoteTitle = "Cancel"
        static let noApprovalThresholdMessage = "No approval threshold was returned for this proposal."
        static let readyToExecuteStatus = "Ready to execute."
        static let terminalOpenInExplorer = "Open in Explorer"
        static let terminalViewRaw = "View raw"
        static let executedAfterThresholdStatus = "Executed after reaching threshold."
        static let thresholdReachedStatus = "Threshold reached."
        static let proposalFactsTitle = "Proposal facts"
        static let typeLabel = "Type"
        static let transactionLabel = "Transaction"
        static let thresholdLabel = "Threshold"
        static let squadLabel = "Squad"
        static let rawInstructionsTitle = "Raw instructions"
        static let rawAccountsTitle = "Raw accounts"
        static let accountsTitle = "Accounts"
        static let rawDataTitle = "Raw data"
        static let actionLabel = "Action"
        static let openInExplorerAccessibilityLabel = "Open Proposal in Explorer"
        static let fromLabel = "from"
        static let toLabel = "to"
        static let programRoleLabel = "Program"
        static let instructionRoleLabel = "Instruction"
        static let proposalRoleLabel = "Proposal"
        static let squadsSource = "Squads"
        static let unknownActionWarning =
            "Cosign could not identify a well-known action. Review the decoded fields and raw details before signing."
        static let firstTimeRecipientWarningTitle = "First-time recipient"

        static func proposalSectionTitle(index: UInt64) -> String {
            "Proposal #\(index)"
        }

        static func proposalSectionTrailing(kind: String, status: String) -> String {
            "\(display(kind)) · \(display(status))"
        }

        static func approvalProgress(approvals: UInt32, threshold: UInt16) -> String {
            "\(approvals) of \(threshold) approvals"
        }

        static func remainingApprovalStatus(remaining: Int) -> String {
            "\(remaining) approval\(remaining == 1 ? "" : "s") needed."
        }

        static func sendTitle(amount: String) -> String {
            "Send \(amount)"
        }

        static func proposalReviewTitle(index: UInt64) -> String {
            "Review proposal #\(index)"
        }

        static func proposalReviewSubtitle(kind: String) -> String {
            "\(display(kind)) proposal"
        }

        static func decodedActionSubtitle(programLabel: String, kind: String) -> String {
            "\(programLabel) · \(display(kind))"
        }

        static func confidenceSourceSubtitle(source: String) -> String {
            "· \(source)"
        }

        static func proposalNumber(index: UInt64) -> String {
            "#\(index)"
        }

        static func proposalFactsSubtitle(kind: String, index: UInt64) -> String {
            "\(display(kind)) · #\(index)"
        }

        static func rawInstructionsSubtitle(count: Int) -> String {
            "\(count) instruction\(count == 1 ? "" : "s")"
        }

        static func rawAccountsSubtitle(count: Int) -> String {
            "\(count) account\(count == 1 ? "" : "s")"
        }

        static func instructionTitle(index: Int) -> String {
            "Instruction \(index)"
        }

        static func voteRingThreshold(_ threshold: UInt16) -> String {
            "/\(threshold)"
        }

        static func display(_ value: String) -> String {
            value
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}

extension CosignCopy {
    enum ProposalActions {
        static let sectionTitle = "Actions"
        static let signerLabel = "Signer"
        static let selectedSignerTitle = "Selected signer"
        static let selectSignerTitle = "Select signer"
        static let selectSignerSubtitle = "Choose the local signer for this proposal action."
        static let finalSignerNote = "final signer"
        static let reviewToApproveTitle = "Review to approve"
        static let moreActionsTitle = "More"
        static let secondaryActionsTitle = "More actions"
        static let secondaryActionsSubtitle = "Choose another action for this proposal."
        static let noLocalSignerTitle = "No local signer for this Squad"
        static let noLocalSignerMessage =
            "Connect or create a signer whose address is a member. Read-only access stays available."
        static let connectSignerTitle = "Connect signer"
        static let noMemberTitle = "You are not a member of this Squad"
        static let noMemberMessage =
            "You can view balances, proposals, and activity. Approve and reject are unavailable."
        static let noActionFallbackMessage = "No actions are available for this signer."

        static func copySelectedSignerAccessibilityLabel() -> String {
            "Copy Selected Signer Address"
        }

        static func actionTitle(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                "Approve"
            case .approveAndExecute:
                "Approve & Execute"
            case .reject:
                "Reject"
            case .cancel:
                "Cancel"
            case .execute:
                "Execute"
            }
        }

        static func permissionTitle(for proposal: SquadProposalDetail, member: SquadMember) -> String {
            if proposal.status.lowercased() == "active", !member.canVote {
                return "You can view but cannot vote"
            }
            if proposal.status.lowercased() == "approved", !member.canExecute {
                return "You can approve but cannot execute"
            }
            return "No action available"
        }
    }
}
