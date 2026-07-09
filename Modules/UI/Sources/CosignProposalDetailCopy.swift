import Foundation
import Squads

extension CosignCopy {
    enum ProposalDetail {
        static func proposedBy(_ proposer: String, createdAtUnix: Int64?) -> String {
            let who = cosignShortAddress(proposer)
            guard let createdAtUnix else {
                return String(localized: "Proposed by \(who)", bundle: .module)
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let when = formatter.localizedString(
                for: Date(timeIntervalSince1970: TimeInterval(createdAtUnix)),
                relativeTo: Date()
            )
            return String(localized: "Proposed by \(who) · \(when)", bundle: .module)
        }

        static let unableToLoadTitle = String(localized: "Unable to Load Proposal", bundle: .module)
        static let retryButtonTitle = String(localized: "Retry", bundle: .module)
        static let decodedFieldsSectionTitle = String(localized: "Decoded fields", bundle: .module)
        static let technicalDetailsSectionTitle = String(localized: "Technical details", bundle: .module)
        static let votesSectionTitle = String(localized: "Votes", bundle: .module)
        static let approvalsSectionTitle = String(localized: "Approvals", bundle: .module)
        static let rejectionsSectionTitle = String(localized: "Rejections", bundle: .module)
        static let cancellationsSectionTitle = String(localized: "Cancellations", bundle: .module)
        static let approveVoteTitle = String(localized: "Approve", bundle: .module)
        static let rejectVoteTitle = String(localized: "Reject", bundle: .module)
        static let cancelVoteTitle = String(localized: "Cancel", bundle: .module)
        static let noApprovalThresholdMessage = String(
            localized: "No approval threshold was returned for this proposal.",
            bundle: .module
        )
        static let readyToExecuteStatus = String(localized: "Ready to execute.", bundle: .module)
        static let terminalOpenInExplorer = String(localized: "Open in Explorer", bundle: .module)
        static let terminalViewRaw = String(localized: "View raw", bundle: .module)
        static let executedAfterThresholdStatus = String(
            localized: "Executed after reaching threshold.",
            bundle: .module
        )
        static let thresholdReachedStatus = String(localized: "Threshold reached.", bundle: .module)
        static let proposalFactsTitle = String(localized: "Proposal facts", bundle: .module)
        static let typeLabel = String(localized: "Type", bundle: .module)
        static let transactionLabel = String(localized: "Transaction", bundle: .module)
        static let thresholdLabel = String(localized: "Threshold", bundle: .module)
        static let squadLabel = String(localized: "Squad", bundle: .module)
        static let rawInstructionsTitle = String(localized: "Raw instructions", bundle: .module)
        static let rawAccountsTitle = String(localized: "Raw accounts", bundle: .module)
        static let accountsTitle = String(localized: "Accounts", bundle: .module)
        static let rawDataTitle = String(localized: "Raw data", bundle: .module)
        static let actionLabel = String(localized: "Action", bundle: .module)
        static let openInExplorerAccessibilityLabel = String(localized: "Open Proposal in Explorer", bundle: .module)
        static let fromLabel = String(localized: "from", bundle: .module)
        static let toLabel = String(localized: "to", bundle: .module)
        static let programRoleLabel = String(localized: "Program", bundle: .module)
        static let instructionRoleLabel = String(localized: "Instruction", bundle: .module)
        static let proposalRoleLabel = String(localized: "Proposal", bundle: .module)
        static let squadsSource = String(localized: "Squads", bundle: .module)
        static let unknownActionWarning =
            String(
                localized: "Cosign could not identify a well-known action. Review the decoded fields and raw details before signing.",
                bundle: .module
            )
        static let firstTimeRecipientWarningTitle = String(localized: "First-time recipient", bundle: .module)
        static let executionFailed = String(
            localized: "This execution failed on-chain and did not settle.",
            bundle: .module
        )

        static func proposalSectionTitle(index: UInt64) -> String {
            String(localized: "Proposal #\(index)", bundle: .module)
        }

        static func proposalSectionTrailing(kind: String, status: String) -> String {
            "\(display(kind)) · \(display(status))"
        }

        static func approvalProgress(approvals: UInt32, threshold: UInt16) -> String {
            String(localized: "\(approvals) of \(threshold) approvals", bundle: .module)
        }

        static func remainingApprovalStatus(remaining: Int) -> String {
            String(localized: "\(remaining) approval\(remaining == 1 ? "" : "s") needed.", bundle: .module)
        }

        static func sendTitle(amount: String) -> String {
            String(localized: "Send \(amount)", bundle: .module)
        }

        static func proposalReviewTitle(index: UInt64) -> String {
            String(localized: "Review proposal #\(index)", bundle: .module)
        }

        static func proposalReviewSubtitle(kind: String) -> String {
            String(localized: "\(display(kind)) proposal", bundle: .module)
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
            String(localized: "\(count) instruction\(count == 1 ? "" : "s")", bundle: .module)
        }

        static func rawAccountsSubtitle(count: Int) -> String {
            String(localized: "\(count) account\(count == 1 ? "" : "s")", bundle: .module)
        }

        static func instructionTitle(index: Int) -> String {
            String(localized: "Instruction \(index)", bundle: .module)
        }

        static let configProposalTitle = String(localized: "Change squad configuration", bundle: .module)
        static func configProposalSubtitle(count: Int) -> String {
            count == 1
                ? String(localized: "1 change to members, permissions, and threshold", bundle: .module)
                : String(localized: "\(count) changes to members, permissions, and threshold", bundle: .module)
        }

        static let configAuthorityBadge = String(localized: "CONFIG · AUTHORITY", bundle: .module)
        static let configChangesSectionTitle = String(localized: "Configuration changes", bundle: .module)
        static let authorityBannerTitle = String(localized: "Changes signing authority", bundle: .module)
        static let authorityBannerBody =
            String(
                localized: "This proposal alters who can sign and how many signatures execute. Review each change below.",
                bundle: .module
            )
        static let configNewChip = String(localized: "New", bundle: .module)
        static let configRemovedNote = String(localized: "No longer a signer", bundle: .module)
        static let configThresholdLabel = String(localized: "Signatures to execute", bundle: .module)
        static let configTimeLockLabel = String(localized: "Time lock", bundle: .module)
        static let configRentCollectorLabel = String(localized: "Rent collector", bundle: .module)
        static let configRentCollectorNone = String(localized: "None", bundle: .module)
        static let configPermissionLabel = String(localized: "Permission", bundle: .module)
        static let configAddLabel = String(localized: "Add", bundle: .module)
        static let configRemoveLabel = String(localized: "Remove", bundle: .module)
        static let configPermissionsNone = String(localized: "None", bundle: .module)
        static let configSigningPowerLabel = String(localized: "Signing power", bundle: .module)
        static let configApprovalRatio = String(localized: "Approval ratio", bundle: .module)
        static let configDerivedTag = String(localized: "DERIVED", bundle: .module)
        static let configLooserChip = String(localized: "Looser", bundle: .module)
        static let configTighterChip = String(localized: "Tighter", bundle: .module)
        static let configNowUnanimousChip = String(localized: "Now unanimous", bundle: .module)

        static func signingPowerCaveat(signatures: Int, looser: Bool) -> String {
            let subject = signatures == 1
                ? String(localized: "1 signature now comes", bundle: .module)
                : String(localized: "\(signatures) signatures now come", bundle: .module)
            let pool = looser
                ? String(localized: "a larger pool, a proportionally looser bar", bundle: .module)
                : String(localized: "a smaller pool", bundle: .module)
            return String(localized: "Threshold unchanged. Same \(subject) from \(pool).", bundle: .module)
        }

        static func configChangesCount(_ count: Int) -> String {
            String(localized: "\(count) · this proposal", bundle: .module)
        }

        static func thresholdDiff(oldValue: Int, oldOf: Int, newValue: Int, newOf: Int) -> String {
            String(localized: "\(oldValue) of \(oldOf) \u{2192} \(newValue) of \(newOf)", bundle: .module)
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
        static let sectionTitle = String(localized: "Actions", bundle: .module)
        static let signerLabel = String(localized: "Signer", bundle: .module)
        static let selectedSignerTitle = String(localized: "Selected signer", bundle: .module)
        static let selectSignerTitle = String(localized: "Select signer", bundle: .module)
        static let selectSignerSubtitle = String(
            localized: "Choose the local signer for this proposal action.",
            bundle: .module
        )
        static let finalSignerNote = String(localized: "final signer", bundle: .module)
        static let reviewToApproveTitle = String(localized: "Review to approve", bundle: .module)
        static let moreActionsTitle = String(localized: "More", bundle: .module)
        static let secondaryActionsTitle = String(localized: "More actions", bundle: .module)
        static let secondaryActionsSubtitle = String(
            localized: "Choose another action for this proposal.",
            bundle: .module
        )
        static let noLocalSignerTitle = String(localized: "No local signer for this Squad", bundle: .module)
        static let noLocalSignerMessage =
            String(
                localized: "Connect or create a signer whose address is a member. Read-only access stays available.",
                bundle: .module
            )
        static let connectSignerTitle = String(localized: "Connect signer", bundle: .module)
        static let noMemberTitle = String(localized: "You are not a member of this Squad", bundle: .module)
        static let noMemberMessage =
            String(
                localized: "You can view balances, proposals, and activity. Approve and reject are unavailable.",
                bundle: .module
            )
        static let noActionFallbackMessage = String(
            localized: "No actions are available for this signer.",
            bundle: .module
        )

        static func copySelectedSignerAccessibilityLabel() -> String {
            String(localized: "Copy Selected Signer Address", bundle: .module)
        }

        static func actionTitle(for action: SquadProposalAction) -> String {
            switch action {
            case .approve:
                String(localized: "Approve", bundle: .module)
            case .approveAndExecute:
                String(localized: "Approve & Execute", bundle: .module)
            case .reject:
                String(localized: "Reject", bundle: .module)
            case .cancel:
                String(localized: "Cancel", bundle: .module)
            case .execute:
                String(localized: "Execute", bundle: .module)
            }
        }

        static func permissionTitle(for proposal: SquadProposalDetail, member: SquadMember) -> String {
            if proposal.status.lowercased() == "active", !member.canVote {
                return String(localized: "You can view but cannot vote", bundle: .module)
            }
            if proposal.status.lowercased() == "approved", !member.canExecute {
                return String(localized: "You can approve but cannot execute", bundle: .module)
            }
            return String(localized: "No action available", bundle: .module)
        }
    }
}
