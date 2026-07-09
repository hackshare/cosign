import Foundation
import Squads

struct ProposalSubmissionResult: Identifiable {
    enum Kind {
        case full
        case partialApproveExecuted
    }

    let id: String
    let action: SquadProposalAction
    let proposalIndex: UInt64?
    let status: String
    let summary: String?
    let signatures: [ProposalSubmissionSignature]
    let kind: Kind

    init(
        action: SquadProposalAction,
        signatures: [ProposalSubmissionSignature],
        status: String,
        proposalIndex: UInt64? = nil,
        summary: String? = nil,
        kind: Kind = .full
    ) {
        id = signatures.map(\.signature).joined(separator: "-")
        self.action = action
        self.proposalIndex = proposalIndex
        self.status = status
        self.summary = summary
        self.signatures = signatures
        self.kind = kind
    }
}

struct ProposalSubmissionSignature: Identifiable {
    var id: String {
        signature
    }

    let label: String
    let signature: String
    let explorerURL: URL?
}
