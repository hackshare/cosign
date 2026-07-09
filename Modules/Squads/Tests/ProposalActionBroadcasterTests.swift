import Foundation
import Testing
@testable import Squads

// MARK: - Fake BroadcastLegRunner

private final class FakeBroadcastLegRunner: BroadcastLegRunner {
    private(set) var signCounts: [SquadProposalAction: Int] = [:]
    private(set) var broadcastCounts: [SquadProposalAction: Int] = [:]

    /// Set > 0 to fail that many broadcasts before succeeding for a given action.
    var broadcastFailuresRemaining: [SquadProposalAction: Int] = [:]

    /// When set, the next signAndSimulate for this action throws simulationFailed (then clears).
    var signThrowsSimulationFailed: SquadProposalAction?

    func signAndSimulate(action: SquadProposalAction) async throws -> SignedProposalTransaction {
        signCounts[action, default: 0] += 1
        if signThrowsSimulationFailed == action {
            signThrowsSimulationFailed = nil
            throw ProposalActionError.simulationFailed("sim error")
        }
        return SignedProposalTransaction(
            action: action,
            messageBytes: Data([0x01]),
            signature: Data([0x02]),
            simulationLogs: []
        )
    }

    func broadcastSigned(_ signed: SignedProposalTransaction) async throws -> ProposalActionSubmittedTransaction {
        let action = signed.action
        broadcastCounts[action, default: 0] += 1
        if let remaining = broadcastFailuresRemaining[action], remaining > 0 {
            broadcastFailuresRemaining[action] = remaining - 1
            throw ProposalActionError.transactionFailed("broadcast failure")
        }
        return ProposalActionSubmittedTransaction(
            action: action,
            signature: "sig-\(action.rawValue)",
            simulationLogs: []
        )
    }

    func finalize(
        action: SquadProposalAction,
        transactions: [ProposalActionSubmittedTransaction]
    ) async throws -> ProposalActionSubmission {
        ProposalActionSubmission(
            action: action,
            transactions: transactions,
            refreshedProposal: SquadProposalSummary(
                transactionIndex: 1,
                status: "executed",
                votesYes: 1,
                votesNo: 0,
                votesCancelled: 0,
                threshold: 1
            )
        )
    }

    func rememberExecution(_: String) {}
}

// MARK: - Tests

struct ProposalActionBroadcasterTests {
    /// Sign called once, broadcast called twice (fail then succeed).
    @Test func singleLegBroadcastRetrySucceeds() async throws {
        let runner = FakeBroadcastLegRunner()
        runner.broadcastFailuresRemaining[.approve] = 1
        let broadcaster = ProposalActionBroadcaster(runner: runner, plan: [.approve], finalAction: .approve)

        do {
            _ = try await broadcaster.run()
            Issue.record("Expected broadcastFailed on attempt 1")
        } catch let ProposalActionError.broadcastFailed(failure) {
            #expect(failure.action == .approve)
            #expect(failure.attempt == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let submission = try await broadcaster.run()
        #expect(submission.transactions.count == 1)
        #expect(runner.signCounts[.approve] == 1, "sign must not be repeated on broadcast retry")
        #expect(runner.broadcastCounts[.approve] == 2, "broadcast called once failing, once succeeding")
    }

    /// Approve landed; execute failed then succeeded. Approve must never be re-submitted.
    @Test func approveLandedExecuteFailedRetriesOnlyExecute() async throws {
        let runner = FakeBroadcastLegRunner()
        runner.broadcastFailuresRemaining[.execute] = 1
        let broadcaster = ProposalActionBroadcaster(
            runner: runner,
            plan: [.approve, .execute],
            finalAction: .approveAndExecute
        )

        do {
            _ = try await broadcaster.run()
            Issue.record("Expected broadcastFailed on execute attempt 1")
        } catch let ProposalActionError.broadcastFailed(failure) {
            #expect(failure.action == .execute)
            #expect(failure.attempt == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let submission = try await broadcaster.run()
        #expect(submission.transactions.count == 2)
        #expect(runner.signCounts[.approve] == 1, "approve must not be re-signed")
        #expect(runner.broadcastCounts[.approve] == 1, "approve must not be re-broadcast")
        #expect(runner.signCounts[.execute] == 1, "execute signed once")
        #expect(runner.broadcastCounts[.execute] == 2, "execute broadcast twice")
    }

    /// Approve failed; retry re-broadcasts approve then continues to execute.
    @Test func approveFailedRetryResumesToExecute() async throws {
        let runner = FakeBroadcastLegRunner()
        runner.broadcastFailuresRemaining[.approve] = 1
        let broadcaster = ProposalActionBroadcaster(
            runner: runner,
            plan: [.approve, .execute],
            finalAction: .approveAndExecute
        )

        do {
            _ = try await broadcaster.run()
            Issue.record("Expected broadcastFailed on approve attempt 1")
        } catch let ProposalActionError.broadcastFailed(failure) {
            #expect(failure.action == .approve)
            #expect(failure.attempt == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let submission = try await broadcaster.run()
        #expect(submission.transactions.count == 2)
        #expect(runner.signCounts[.approve] == 1, "approve signed once")
        #expect(runner.broadcastCounts[.approve] == 2, "approve broadcast twice (fail then succeed)")
        #expect(runner.signCounts[.execute] == 1, "execute signed once")
        #expect(runner.broadcastCounts[.execute] == 1, "execute broadcast once")
    }

    /// A pre-signature failure propagates as-is (not wrapped in broadcastFailed),
    /// and pending stays nil so a subsequent run() re-signs.
    @Test func preSignatureErrorNotWrappedAsBroadcastFailed() async throws {
        let runner = FakeBroadcastLegRunner()
        runner.signThrowsSimulationFailed = .approve
        let broadcaster = ProposalActionBroadcaster(runner: runner, plan: [.approve], finalAction: .approve)

        do {
            _ = try await broadcaster.run()
            Issue.record("Expected simulationFailed to be thrown")
        } catch ProposalActionError.simulationFailed {
            // correct — not wrapped as broadcastFailed
        } catch {
            Issue.record("Wrong error type, got: \(error)")
        }

        // pending stays nil, so the next run() re-signs
        let submission = try await broadcaster.run()
        #expect(runner.signCounts[.approve] == 2, "sign attempted again after pre-signature error")
        #expect(submission.transactions.count == 1)
    }
}
