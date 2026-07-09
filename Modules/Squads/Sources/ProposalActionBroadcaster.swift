import Foundation

/// Injectable seam — tests inject a fake; production uses SquadsBroadcastLegRunner.
protocol BroadcastLegRunner: AnyObject {
    func signAndSimulate(action: SquadProposalAction) async throws -> SignedProposalTransaction
    func broadcastSigned(_ signed: SignedProposalTransaction) async throws -> ProposalActionSubmittedTransaction
    func finalize(
        action: SquadProposalAction,
        transactions: [ProposalActionSubmittedTransaction]
    ) async throws -> ProposalActionSubmission
    func rememberExecution(_ signature: String)
}

/// Drives a proposal action's transaction legs and resumes after a broadcast failure.
///
/// Each leg is signed at most once. On a broadcast failure the signed bytes are
/// retained so that a subsequent `run()` can retry the broadcast without re-signing.
public final class ProposalActionBroadcaster: @unchecked Sendable {
    private let runner: BroadcastLegRunner
    private let plan: [SquadProposalAction]
    private let finalAction: SquadProposalAction
    private var completed: [ProposalActionSubmittedTransaction] = []
    private var pending: SignedProposalTransaction?
    public private(set) var attempt = 0

    public var completedTransactions: [ProposalActionSubmittedTransaction] {
        completed
    }

    init(runner: BroadcastLegRunner, plan: [SquadProposalAction], finalAction: SquadProposalAction) {
        self.runner = runner
        self.plan = plan
        self.finalAction = finalAction
    }

    /// Runs or resumes the broadcast sequence.
    ///
    /// - Throws: `ProposalActionError.broadcastFailed` if a leg is submitted to the
    ///   network but confirmation fails. The signed bytes are retained so the next
    ///   `run()` retries only that broadcast. Any error thrown by `signAndSimulate`
    ///   propagates as-is and leaves `pending` nil, causing a fresh sign on the next call.
    public func run() async throws -> ProposalActionSubmission {
        attempt += 1
        for action in plan.dropFirst(completed.count) {
            let signed: SignedProposalTransaction = if let pending, pending.action == action {
                pending
            } else {
                try await runner.signAndSimulate(action: action)
            }
            do {
                let submitted = try await runner.broadcastSigned(signed)
                completed.append(submitted)
                pending = nil
                if action == .execute {
                    runner.rememberExecution(submitted.signature)
                }
            } catch {
                pending = signed
                throw ProposalActionError.broadcastFailed(
                    BroadcastFailure(action: action, reason: broadcastReason(error), attempt: attempt)
                )
            }
        }
        return try await runner.finalize(action: finalAction, transactions: completed)
    }
}

private func broadcastReason(_ error: Error) -> String {
    if case let ProposalActionError.confirmationTimedOut(sig) = error {
        return "Transaction submitted but not yet confirmed: \(sig)"
    }
    if case let ProposalActionError.transactionFailed(msg) = error {
        return msg
    }
    return error.localizedDescription
}
