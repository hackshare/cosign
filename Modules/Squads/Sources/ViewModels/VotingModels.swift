import CosignCore
import Foundation

public enum SquadProposalAction: String, CaseIterable, Identifiable, Sendable {
    case approve
    case approveAndExecute
    case reject
    case cancel
    case execute

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .approve: "Approve"
        case .approveAndExecute: "Approve & Execute"
        case .reject: "Reject"
        case .cancel: "Cancel"
        case .execute: "Execute"
        }
    }

    var coreVoteType: VoteType? {
        switch self {
        case .approve: .approve
        case .reject: .reject
        case .cancel: .cancel
        case .approveAndExecute, .execute: nil
        }
    }
}

public struct ProposalActionSubmittedTransaction: Equatable, Sendable {
    public let action: SquadProposalAction
    public let signature: String
    public let simulationLogs: [String]

    public init(action: SquadProposalAction, signature: String, simulationLogs: [String]) {
        self.action = action
        self.signature = signature
        self.simulationLogs = simulationLogs
    }
}

public struct ProposalActionSubmission: Equatable, Sendable {
    public let action: SquadProposalAction
    public let transactions: [ProposalActionSubmittedTransaction]
    public let refreshedProposal: SquadProposalSummary

    public init(
        action: SquadProposalAction,
        transactions: [ProposalActionSubmittedTransaction],
        refreshedProposal: SquadProposalSummary
    ) {
        self.action = action
        self.transactions = transactions
        self.refreshedProposal = refreshedProposal
    }
}

public enum ProposalActionError: Error, Equatable, Sendable {
    case signerNotMember(String)
    case missingPermission(SquadProposalAction)
    case alreadyVoted(String)
    case actionUnavailable(SquadProposalAction, status: String)
    case proposalChanged(SquadProposalSummary)
    case simulationFailed(String)
    case transactionFailed(String)
    case confirmationTimedOut(String)
}

extension ProposalActionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .signerNotMember(address):
            """
            The selected signer is not a member of this Squad on the current RPC endpoint. \
            Check Settings if \(address) should belong to this Squad.
            """
        case let .missingPermission(action):
            "The selected signer does not have permission to \(action.label.lowercased()) this proposal."
        case let .alreadyVoted(message):
            message
        case let .actionUnavailable(action, status):
            "\(action.label) is not available while the proposal is \(status.lowercased())."
        case .proposalChanged:
            "The proposal changed before signing. Review the latest state and try again."
        case let .simulationFailed(message):
            "Simulation failed: \(message)"
        case let .transactionFailed(message):
            "Transaction failed: \(message)"
        case let .confirmationTimedOut(signature):
            "Transaction submitted but was not confirmed yet: \(signature)"
        }
    }
}

public enum ProposalVoteState: Equatable, Sendable {
    case approved
    case rejected
    case cancelled

    public var displayText: String {
        switch self {
        case .approved:
            "approved"
        case .rejected:
            "rejected"
        case .cancelled:
            "cancelled"
        }
    }
}

public func availableProposalActions(
    for proposal: SquadProposalDetail,
    member: SquadMember
) -> [SquadProposalAction] {
    switch proposal.status.lowercased() {
    case "active":
        guard member.canVote, proposal.voteState(for: member.pubkey) == nil else {
            return []
        }
        var actions: [SquadProposalAction] = [.approve]
        if proposal.canBeApprovedAndExecuted(by: member) {
            actions.append(.approveAndExecute)
        }
        actions.append(.reject)
        return actions
    case "approved":
        var actions = [SquadProposalAction]()
        if member.canExecute {
            actions.append(.execute)
        }
        if member.canVote, proposal.voteState(for: member.pubkey) != .cancelled {
            actions.append(.cancel)
        }
        return actions
    default:
        return []
    }
}

public func proposalActionUnavailableMessage(
    for proposal: SquadProposalDetail,
    member: SquadMember
) -> String? {
    switch proposal.status.lowercased() {
    case "active":
        if let voteState = proposal.voteState(for: member.pubkey) {
            return "The selected signer already \(voteState.displayText) this proposal."
        }
        if !member.canVote {
            return "The selected signer is a member, but does not have vote permission."
        }
        return nil
    case "approved":
        if member.canVote || member.canExecute {
            return nil
        }
        return "The selected signer is a member, but cannot execute or cancel proposals."
    default:
        return "No actions are available while this proposal is \(proposal.status.lowercased())."
    }
}

public extension SquadProposalAction {
    func isPermitted(by member: SquadMember) -> Bool {
        switch self {
        case .approve, .reject, .cancel:
            member.canVote
        case .approveAndExecute:
            member.canVote && member.canExecute
        case .execute:
            member.canExecute
        }
    }
}

public extension SquadProposalDetail {
    func voteState(for memberPubkey: String) -> ProposalVoteState? {
        if votersYes.contains(memberPubkey) {
            return .approved
        }
        if votersNo.contains(memberPubkey) {
            return .rejected
        }
        if votersCancelled.contains(memberPubkey) {
            return .cancelled
        }
        return nil
    }

    func canBeApprovedAndExecuted(by member: SquadMember) -> Bool {
        guard
            status.lowercased() == "active",
            member.canVote,
            member.canExecute,
            voteState(for: member.pubkey) == nil,
            threshold > 0
        else {
            return false
        }

        let thresholdCount = UInt32(threshold)
        return votesYes < thresholdCount && votesYes >= thresholdCount - 1
    }
}
