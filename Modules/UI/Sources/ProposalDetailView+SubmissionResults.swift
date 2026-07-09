import Indexer
import Squads

extension ProposalDetailView {
    func submissionResult(
        for request: ProposalSigningRequest,
        submission: ProposalActionSubmission
    ) -> ProposalSubmissionResult {
        ProposalSubmissionResult(
            action: request.action,
            signatures: submission.transactions.map(signatureRecord),
            status: submission.refreshedProposal.status,
            proposalIndex: submission.refreshedProposal.transactionIndex,
            summary: receiptSummary(
                for: request.action,
                instructionSummary: submission.refreshedProposal.action?.summary
            )
        )
    }

    private func receiptSummary(for action: SquadProposalAction, instructionSummary: String?) -> String? {
        guard action == .approveAndExecute || action == .execute else {
            return nil
        }
        return instructionSummary
    }

    func demoSubmissionResult(
        for request: ProposalSigningRequest,
        proposal: SquadProposalDetail
    ) -> ProposalSubmissionResult {
        let actions: [SquadProposalAction] = request.action == .approveAndExecute
            ? [.approve, .execute]
            : [request.action]
        let signatures = actions.enumerated().map { offset, action in
            let signature = demoSignature(
                action: action,
                proposalIndex: proposal.transactionIndex,
                offset: offset
            )
            return signatureRecord(label: action.label, signature: signature)
        }
        return ProposalSubmissionResult(
            action: request.action,
            signatures: signatures,
            status: demoStatus(after: request.action, proposal: proposal),
            proposalIndex: proposal.transactionIndex,
            summary: receiptSummary(
                for: request.action,
                instructionSummary: proposal.instructions.first?.summary
            )
        )
    }

    func partialSubmissionResult(
        approveTransaction: ProposalActionSubmittedTransaction,
        proposalIndex: UInt64?
    ) -> ProposalSubmissionResult {
        ProposalSubmissionResult(
            action: .approveAndExecute,
            signatures: [signatureRecord(approveTransaction)],
            status: "approved",
            proposalIndex: proposalIndex,
            kind: .partialApproveExecuted
        )
    }

    private func signatureRecord(_ transaction: ProposalActionSubmittedTransaction) -> ProposalSubmissionSignature {
        signatureRecord(label: transaction.action.label, signature: transaction.signature)
    }

    private func signatureRecord(label: String, signature: String) -> ProposalSubmissionSignature {
        ProposalSubmissionSignature(
            label: label,
            signature: signature,
            explorerURL: SolanaExplorer.transactionURL(
                signature: signature,
                rpcURL: indexerEnvironment.effectiveExplorerRPCURL
            )
        )
    }

    private func demoStatus(after action: SquadProposalAction, proposal: SquadProposalDetail) -> String {
        switch action {
        case .approveAndExecute, .execute:
            "Executed"
        case .approve:
            Int(proposal.votesYes) + 1 >= Int(proposal.threshold) ? "Approved" : proposal.status
        case .reject:
            proposal.status
        case .cancel:
            "Cancelled"
        }
    }

    private func demoSignature(action: SquadProposalAction, proposalIndex: UInt64, offset: Int) -> String {
        CosignDemoSubmissionSignature.signature(
            kind: demoSignatureKind(for: action),
            proposalIndex: proposalIndex,
            offset: offset
        )
    }

    private func demoSignatureKind(for action: SquadProposalAction) -> CosignDemoSubmissionSignatureKind {
        switch action {
        case .approve:
            .approve
        case .approveAndExecute:
            .approveAndExecute
        case .execute:
            .execute
        case .reject:
            .reject
        case .cancel:
            .cancel
        }
    }
}
