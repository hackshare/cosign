import Core
import CosignCore
import Foundation

public extension SquadsService {
    func submitTransferProposal(
        _ draft: TransferProposalDraft,
        in squadAddress: String,
        signer: any Signer
    ) async throws -> ProposalCreationSubmission {
        switch draft {
        case let .sol(draft):
            try await submitSOLTransferProposal(draft, in: squadAddress, signer: signer)
        case let .token(draft):
            try await submitTokenTransferProposal(draft, in: squadAddress, signer: signer)
        }
    }

    func submitSOLTransferProposal(
        _ draft: SOLTransferProposalDraft,
        in squadAddress: String,
        signer: any Signer
    ) async throws -> ProposalCreationSubmission {
        guard draft.lamports > 0 else {
            throw ProposalCreationError.invalidAmount
        }

        let memberPubkey = CosignCore.base58(signer.pubkey)
        let detail = try await detail(of: squadAddress)
        try validateProposalCreation(draft, detail: detail, memberPubkey: memberPubkey)

        var request = SOLTransferProposalTransactionRequest()
        request.rpcURL = rpcURL
        request.multisigAddress = squadAddress
        request.vaultIndex = draft.vaultIndex
        request.memberPubkey = memberPubkey
        request.recipientPubkey = draft.recipient
        request.lamports = draft.lamports
        request.memo = draft.memo
        let prepared = try CosignCore.buildSquadsSOLTransferProposalTransaction(request)
        let signatureBytes = try await signer.sign(message: prepared.messageBytes)
        try simulateProposalCreation(prepared, signatureBytes: signatureBytes)
        return try await submitPreparedProposalCreation(
            prepared,
            signatureBytes: signatureBytes,
            squadAddress: squadAddress
        )
    }

    func submitTokenTransferProposal(
        _ draft: TokenTransferProposalDraft,
        in squadAddress: String,
        signer: any Signer
    ) async throws -> ProposalCreationSubmission {
        guard draft.amount > 0 else {
            throw ProposalCreationError.invalidAmount
        }

        let memberPubkey = CosignCore.base58(signer.pubkey)
        let detail = try await detail(of: squadAddress)
        try validateProposalCreation(vaultIndex: draft.vaultIndex, detail: detail, memberPubkey: memberPubkey)

        var request = TokenTransferProposalTransactionRequest()
        request.rpcURL = rpcURL
        request.multisigAddress = squadAddress
        request.vaultIndex = draft.vaultIndex
        request.memberPubkey = memberPubkey
        request.recipientOwnerPubkey = draft.recipientOwner
        request.mintPubkey = draft.mint
        request.amount = draft.amount
        request.decimals = draft.decimals
        request.tokenProgramID = draft.tokenProgramID
        request.memo = draft.memo
        let prepared = try CosignCore.buildSquadsTokenTransferProposalTransaction(request)
        let signatureBytes = try await signer.sign(message: prepared.messageBytes)
        try simulateProposalCreation(prepared, signatureBytes: signatureBytes)
        return try await submitPreparedProposalCreation(
            prepared,
            signatureBytes: signatureBytes,
            squadAddress: squadAddress
        )
    }

    private func validateProposalCreation(
        _ draft: SOLTransferProposalDraft,
        detail: SquadDetail,
        memberPubkey: String
    ) throws {
        try validateProposalCreation(vaultIndex: draft.vaultIndex, detail: detail, memberPubkey: memberPubkey)
    }

    private func validateProposalCreation(
        vaultIndex: UInt8,
        detail: SquadDetail,
        memberPubkey: String
    ) throws {
        guard let member = detail.members.first(where: { $0.pubkey == memberPubkey }) else {
            throw ProposalCreationError.signerNotMember(memberPubkey)
        }
        guard member.canInitiate else {
            throw ProposalCreationError.missingInitiatePermission
        }
        guard detail.vaults.contains(where: { $0.ref.index == vaultIndex }) else {
            throw ProposalCreationError.vaultNotFound(vaultIndex)
        }
    }

    func simulateProposalCreation(
        _ prepared: PreparedProposalCreation,
        signatureBytes: Data
    ) throws {
        let simulation = try CosignCore.simulateSquadsTransaction(
            rpcURL: rpcURL,
            messageBytes: prepared.messageBytes,
            signatureBytes: signatureBytes
        )
        if let err = simulation.err {
            throw ProposalCreationError.simulationFailed(readableSimulationError(err))
        }
    }

    private func waitForProposalCreation(signature: String) async throws {
        do {
            try await waitForConfirmation(signature: signature)
        } catch let ProposalActionError.confirmationTimedOut(signature) {
            throw ProposalCreationError.confirmationTimedOut(signature)
        } catch let ProposalActionError.transactionFailed(message) {
            throw ProposalCreationError.transactionFailed(message)
        }
    }

    func submitPreparedProposalCreation(
        _ prepared: PreparedProposalCreation,
        signatureBytes: Data,
        squadAddress: String
    ) async throws -> ProposalCreationSubmission {
        let submission = try CosignCore.sendSquadsTransaction(
            rpcURL: rpcURL,
            messageBytes: prepared.messageBytes,
            signatureBytes: signatureBytes
        )
        try await waitForProposalCreation(signature: submission.signature)
        await clearReadCaches()

        let proposal = try? await proposal(in: squadAddress, transactionIndex: prepared.transactionIndex)
        return ProposalCreationSubmission(
            signature: submission.signature,
            transactionIndex: prepared.transactionIndex,
            proposalAddress: prepared.proposalAddress,
            transactionAddress: prepared.transactionAddress,
            vaultAddress: prepared.vaultAddress,
            proposal: proposal
        )
    }
}
