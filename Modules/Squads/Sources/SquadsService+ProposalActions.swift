import Core
import CosignCore
import Foundation

public extension SquadsService {
    func executionSignature(in squadAddress: String, transactionIndex: UInt64) -> String? {
        if let demoSignature = demoFixture?.executionSignature(
            in: squadAddress,
            transactionIndex: transactionIndex
        ) {
            return demoSignature
        }
        return executionSignatureCache.signature(in: squadAddress, transactionIndex: transactionIndex)
    }

    /// Validates the action up-front and returns a broadcaster ready to execute the leg plan.
    ///
    /// For `.approveAndExecute` the plan is `[.approve, .execute]`; for any other action
    /// the plan is the single action. Call `run()` on the returned broadcaster to execute;
    /// call it again to retry a failed broadcast without re-signing.
    func makeBroadcaster(
        _ action: SquadProposalAction,
        in squadAddress: String,
        transactionIndex: UInt64,
        signer: any Signer,
        displayedProposal: SquadProposalDetail? = nil
    ) async throws -> ProposalActionBroadcaster {
        let memberPubkey = CosignCore.base58(signer.pubkey)
        let currentProposal = try await proposal(in: squadAddress, transactionIndex: transactionIndex)
        let squadMembers = try await members(of: squadAddress)
        guard let member = squadMembers.first(where: { $0.pubkey == memberPubkey }) else {
            throw ProposalActionError.signerNotMember(memberPubkey)
        }
        try validateAction(action, for: currentProposal, member: member)
        let displayedSummary = displayedProposal.map(SquadProposalSummary.init(detail:))
        if let displayedSummary, !currentProposal.matches(displayedSummary) {
            throw ProposalActionError.proposalChanged(SquadProposalSummary(detail: currentProposal))
        }

        let plan: [SquadProposalAction] = action == .approveAndExecute ? [.approve, .execute] : [action]
        let runner: any BroadcastLegRunner = if let broadcastMode = demoBroadcastMode {
            DemoBroadcastLegRunner(
                mode: broadcastMode,
                proposalSummary: SquadProposalSummary(detail: currentProposal)
            )
        } else {
            SquadsBroadcastLegRunner(
                service: self,
                squadAddress: squadAddress,
                transactionIndex: transactionIndex,
                memberPubkey: memberPubkey,
                signer: signer
            )
        }
        return ProposalActionBroadcaster(runner: runner, plan: plan, finalAction: action)
    }
}

extension SquadsService {
    func signAndSimulate(
        action: SquadProposalAction,
        squadAddress: String,
        transactionIndex: UInt64,
        memberPubkey: String,
        signer: any Signer
    ) async throws -> SignedProposalTransaction {
        let prepared = try buildPreparedTransaction(
            action: action, squadAddress: squadAddress,
            transactionIndex: transactionIndex, memberPubkey: memberPubkey
        )
        let signatureBytes = try await signer.sign(message: prepared.messageBytes)
        let simulation = try CosignCore.simulateSquadsTransaction(
            rpcURL: rpcURL, messageBytes: prepared.messageBytes, signatureBytes: signatureBytes
        )
        if let err = simulation.err {
            throw ProposalActionError.simulationFailed(readableSimulationError(err))
        }
        return SignedProposalTransaction(
            action: action, messageBytes: prepared.messageBytes,
            signature: signatureBytes, simulationLogs: simulation.logs
        )
    }

    func broadcastSigned(_ signed: SignedProposalTransaction) async throws -> ProposalActionSubmittedTransaction {
        let submission = try CosignCore.sendSquadsTransaction(
            rpcURL: rpcURL, messageBytes: signed.messageBytes, signatureBytes: signed.signature
        )
        try await waitForConfirmation(signature: submission.signature)
        return ProposalActionSubmittedTransaction(
            action: signed.action, signature: submission.signature, simulationLogs: signed.simulationLogs
        )
    }

    func rememberExecutionSignature(
        _ signature: String,
        in squadAddress: String,
        transactionIndex: UInt64
    ) {
        executionSignatureCache.remember(signature, in: squadAddress, transactionIndex: transactionIndex)
    }

    func buildPreparedTransaction(
        action: SquadProposalAction,
        squadAddress: String,
        transactionIndex: UInt64,
        memberPubkey: String
    ) throws -> PreparedTransaction {
        if action == .execute {
            return try CosignCore.buildSquadsExecuteTransaction(
                rpcURL: rpcURL,
                multisigAddress: squadAddress,
                transactionIndex: transactionIndex,
                memberPubkey: memberPubkey
            )
        }

        guard let vote = action.coreVoteType else {
            throw ProposalActionError.transactionFailed("Unsupported proposal action.")
        }

        return try CosignCore.buildSquadsVoteTransaction(
            rpcURL: rpcURL,
            multisigAddress: squadAddress,
            transactionIndex: transactionIndex,
            memberPubkey: memberPubkey,
            vote: vote
        )
    }

    func validateAction(
        _ action: SquadProposalAction,
        for proposal: SquadProposalDetail,
        member: SquadMember
    ) throws {
        guard action.isPermitted(by: member) else {
            throw ProposalActionError.missingPermission(action)
        }

        let actions = availableProposalActions(for: proposal, member: member)
        if actions.contains(action) {
            return
        }

        if let voteState = proposal.voteState(for: member.pubkey), proposal.status.lowercased() == "active" {
            throw ProposalActionError.alreadyVoted(
                "The selected signer already \(voteState.displayText) this proposal."
            )
        }

        throw ProposalActionError.actionUnavailable(action, status: proposal.status)
    }
}

// MARK: - Production BroadcastLegRunner

private final class SquadsBroadcastLegRunner: BroadcastLegRunner, @unchecked Sendable {
    private let service: SquadsService
    private let squadAddress: String
    private let transactionIndex: UInt64
    private let memberPubkey: String
    private let signer: any Signer
    private var lastRefreshed: SquadProposalSummary?

    init(
        service: SquadsService,
        squadAddress: String,
        transactionIndex: UInt64,
        memberPubkey: String,
        signer: any Signer
    ) {
        self.service = service
        self.squadAddress = squadAddress
        self.transactionIndex = transactionIndex
        self.memberPubkey = memberPubkey
        self.signer = signer
    }

    func signAndSimulate(action: SquadProposalAction) async throws -> SignedProposalTransaction {
        let prepared = try service.buildPreparedTransaction(
            action: action, squadAddress: squadAddress,
            transactionIndex: transactionIndex, memberPubkey: memberPubkey
        )
        // Drift is checked up-front in makeBroadcaster against fresh on-chain state.
        // It must NOT be re-checked per leg: for approveAndExecute the execute leg
        // is built after the user's own approve has landed, so a per-leg check would
        // read that self-inflicted change as drift and throw after approve broadcast.
        lastRefreshed = SquadProposalSummary(record: prepared.refreshedProposal)
        return try await service.signAndSimulate(
            action: action, squadAddress: squadAddress,
            transactionIndex: transactionIndex, memberPubkey: memberPubkey,
            signer: signer
        )
    }

    func broadcastSigned(_ signed: SignedProposalTransaction) async throws -> ProposalActionSubmittedTransaction {
        try await service.broadcastSigned(signed)
    }

    func finalize(
        action: SquadProposalAction,
        transactions: [ProposalActionSubmittedTransaction]
    ) async throws -> ProposalActionSubmission {
        await service.clearReadCaches()
        let latestProposal = try? await service.proposal(in: squadAddress, transactionIndex: transactionIndex)
        let refreshedProposal = latestProposal.map(SquadProposalSummary.init(detail:))
            ?? lastRefreshed
            ?? SquadProposalSummary(
                transactionIndex: transactionIndex,
                status: "unknown",
                votesYes: 0,
                votesNo: 0,
                votesCancelled: 0,
                threshold: 0
            )
        return ProposalActionSubmission(
            action: action,
            transactions: transactions,
            refreshedProposal: refreshedProposal
        )
    }

    func rememberExecution(_ signature: String) {
        service.rememberExecutionSignature(signature, in: squadAddress, transactionIndex: transactionIndex)
    }
}
