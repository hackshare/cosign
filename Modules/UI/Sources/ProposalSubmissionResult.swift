import Foundation
import Squads

struct ProposalSubmissionResult: Identifiable {
    let id: String
    let action: SquadProposalAction
    let proposalIndex: UInt64?
    let status: String
    let summary: String?
    let signatures: [ProposalSubmissionSignature]

    init(
        action: SquadProposalAction,
        signatures: [ProposalSubmissionSignature],
        status: String,
        proposalIndex: UInt64? = nil,
        summary: String? = nil
    ) {
        id = signatures.map(\.signature).joined(separator: "-")
        self.action = action
        self.proposalIndex = proposalIndex
        self.status = status
        self.summary = summary
        self.signatures = signatures
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
