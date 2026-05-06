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

    func submitProposalAction(
        _ action: SquadProposalAction,
        in squadAddress: String,
        transactionIndex: UInt64,
        signer: any Signer,
        displayedProposal: SquadProposalDetail? = nil
    ) async throws -> ProposalActionSubmission {
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

        if action == .approveAndExecute {
            return try await submitApproveAndExecute(
                in: squadAddress,
                transactionIndex: transactionIndex,
                signer: signer,
                memberPubkey: memberPubkey,
                displayedProposal: displayedProposal
            )
        }

        return try await submitSingleAction(
            action,
            in: squadAddress,
            transactionIndex: transactionIndex,
            signer: signer,
            displayedProposal: displayedProposal
        )
    }
}

extension SquadsService {
    func submitSingleAction(
        _ action: SquadProposalAction,
        in squadAddress: String,
        transactionIndex: UInt64,
        signer: any Signer,
        displayedProposal: SquadProposalDetail?
    ) async throws -> ProposalActionSubmission {
        let memberPubkey = CosignCore.base58(signer.pubkey)
        let prepared = try buildPreparedTransaction(
            action: action,
            squadAddress: squadAddress,
            transactionIndex: transactionIndex,
            memberPubkey: memberPubkey
        )
        let refreshed = SquadProposalSummary(record: prepared.refreshedProposal)
        if let displayedProposal, !displayedProposal.matches(refreshed) {
            throw ProposalActionError.proposalChanged(refreshed)
        }

        let submittedTransaction = try await submitPreparedTransaction(
            prepared,
            action: action,
            signer: signer
        )
        if action == .execute {
            rememberExecutionSignature(
                submittedTransaction.signature,
                in: squadAddress,
                transactionIndex: transactionIndex
            )
        }
        await clearReadCaches()
        let latestProposal = try? await proposal(in: squadAddress, transactionIndex: transactionIndex)

        return ProposalActionSubmission(
            action: action,
            transactions: [submittedTransaction],
            refreshedProposal: latestProposal.map(SquadProposalSummary.init(detail:)) ?? refreshed
        )
    }

    func submitApproveAndExecute(
        in squadAddress: String,
        transactionIndex: UInt64,
        signer: any Signer,
        memberPubkey: String,
        displayedProposal: SquadProposalDetail?
    ) async throws -> ProposalActionSubmission {
        let approve = try buildPreparedTransaction(
            action: .approve,
            squadAddress: squadAddress,
            transactionIndex: transactionIndex,
            memberPubkey: memberPubkey
        )
        let refreshed = SquadProposalSummary(record: approve.refreshedProposal)
        if let displayedProposal, !displayedProposal.matches(refreshed) {
            throw ProposalActionError.proposalChanged(refreshed)
        }

        let approveSubmission = try await submitPreparedTransaction(
            approve,
            action: .approve,
            signer: signer
        )
        let execute = try buildPreparedTransaction(
            action: .execute,
            squadAddress: squadAddress,
            transactionIndex: transactionIndex,
            memberPubkey: memberPubkey
        )
        let executeSubmission = try await submitPreparedTransaction(
            execute,
            action: .execute,
            signer: signer
        )
        rememberExecutionSignature(
            executeSubmission.signature,
            in: squadAddress,
            transactionIndex: transactionIndex
        )
        await clearReadCaches()
        let latestProposal = try? await proposal(in: squadAddress, transactionIndex: transactionIndex)

        return ProposalActionSubmission(
            action: .approveAndExecute,
            transactions: [approveSubmission, executeSubmission],
            refreshedProposal: latestProposal.map(SquadProposalSummary.init(detail:)) ?? SquadProposalSummary(
                record: execute.refreshedProposal
            )
        )
    }

    func submitPreparedTransaction(
        _ prepared: PreparedTransaction,
        action: SquadProposalAction,
        signer: any Signer
    ) async throws -> ProposalActionSubmittedTransaction {
        let signatureBytes = try await signer.sign(message: prepared.messageBytes)
        let simulation = try CosignCore.simulateSquadsTransaction(
            rpcURL: rpcURL,
            messageBytes: prepared.messageBytes,
            signatureBytes: signatureBytes
        )
        if let err = simulation.err {
            throw ProposalActionError.simulationFailed(readableSimulationError(err))
        }

        let submission = try CosignCore.sendSquadsTransaction(
            rpcURL: rpcURL,
            messageBytes: prepared.messageBytes,
            signatureBytes: signatureBytes
        )
        try await waitForConfirmation(signature: submission.signature)
        return ProposalActionSubmittedTransaction(
            action: action,
            signature: submission.signature,
            simulationLogs: simulation.logs
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
