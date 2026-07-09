import Foundation

/// Mode for the demo broadcast-failure seam.
public enum DemoBroadcastMode: Equatable, Sendable {
    /// Fails the first broadcast attempt, succeeds on the second.
    case retryable
    /// Always fails; drives the terminal (3-attempt) error state.
    case terminal
    /// Succeeds approve/reject/single legs but always fails the execute leg.
    /// Used to drive the partial-receipt path (approve landed, execute did not).
    case executeOnly
}

/// Fake `BroadcastLegRunner` for demo broadcast-failure walkthroughs.
///
/// Signs and simulates instantly with synthetic bytes so no Signer or RPC call
/// is needed. Broadcast behavior depends on `mode`.
final class DemoBroadcastLegRunner: BroadcastLegRunner, @unchecked Sendable {
    private let mode: DemoBroadcastMode
    private let proposalSummary: SquadProposalSummary
    private var broadcastAttempts = 0

    init(mode: DemoBroadcastMode, proposalSummary: SquadProposalSummary) {
        self.mode = mode
        self.proposalSummary = proposalSummary
    }

    func signAndSimulate(action: SquadProposalAction) async throws -> SignedProposalTransaction {
        SignedProposalTransaction(
            action: action,
            messageBytes: Data(repeating: 0xAB, count: 64),
            signature: Data(repeating: 0xCD, count: 64),
            simulationLogs: []
        )
    }

    func broadcastSigned(_ signed: SignedProposalTransaction) async throws -> ProposalActionSubmittedTransaction {
        if mode == .executeOnly {
            if signed.action == .execute {
                throw ProposalActionError.transactionFailed("RPC timeout · 504")
            }
            return ProposalActionSubmittedTransaction(
                action: signed.action,
                signature: "DemoBroadcastSig1111111111111111111111111111111111111111111111111111",
                simulationLogs: []
            )
        }

        broadcastAttempts += 1
        guard mode == .retryable, broadcastAttempts >= 2 else {
            throw ProposalActionError.transactionFailed("RPC timeout · 504")
        }
        return ProposalActionSubmittedTransaction(
            action: signed.action,
            signature: "DemoBroadcastSig1111111111111111111111111111111111111111111111111111",
            simulationLogs: []
        )
    }

    func finalize(
        action: SquadProposalAction,
        transactions: [ProposalActionSubmittedTransaction]
    ) async throws -> ProposalActionSubmission {
        let refreshed = SquadProposalSummary(
            transactionIndex: proposalSummary.transactionIndex,
            status: "Executed",
            votesYes: UInt32(proposalSummary.threshold),
            votesNo: 0,
            votesCancelled: 0,
            threshold: proposalSummary.threshold,
            kind: proposalSummary.kind,
            action: proposalSummary.action
        )
        return ProposalActionSubmission(action: action, transactions: transactions, refreshedProposal: refreshed)
    }

    func rememberExecution(_: String) {}
}
