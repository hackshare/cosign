import CosignCore
import Indexer

extension SquadSummary {
    init(record: RelaySquadSummary) {
        self.init(
            address: record.address,
            displayName: record.displayName,
            threshold: record.threshold,
            memberCount: record.memberCount,
            transactionIndex: record.transactionIndex,
            staleTransactionIndex: record.staleTransactionIndex
        )
    }
}

extension SquadMember {
    init(record: RelaySquadMember) {
        self.init(
            pubkey: record.pubkey,
            canInitiate: record.canInitiate,
            canVote: record.canVote,
            canExecute: record.canExecute
        )
    }
}

extension SquadVaultRef {
    init(record: RelaySquadVaultRef) {
        self.init(index: record.index, address: record.address)
    }
}

extension SquadProposalSummary {
    init(record: ProposalSummary) {
        self.init(
            transactionIndex: record.transactionIndex,
            status: record.status,
            votesYes: record.votesYes,
            votesNo: record.votesNo,
            votesCancelled: record.votesCancelled,
            threshold: record.threshold,
            kind: nil,
            action: nil
        )
    }

    init(record: RelayProposalSummary) {
        self.init(
            transactionIndex: record.transactionIndex,
            status: record.status,
            votesYes: record.votesYes,
            votesNo: record.votesNo,
            votesCancelled: record.votesCancelled,
            threshold: record.threshold,
            kind: record.kind,
            action: record.action
        )
    }

    init(detail: SquadProposalDetail) {
        self.init(
            transactionIndex: detail.transactionIndex,
            status: detail.status,
            votesYes: detail.votesYes,
            votesNo: detail.votesNo,
            votesCancelled: detail.votesCancelled,
            threshold: detail.threshold,
            kind: detail.kind,
            action: nil
        )
    }
}

extension SquadProposalDetail {
    func matches(_ summary: SquadProposalSummary) -> Bool {
        transactionIndex == summary.transactionIndex
            && status == summary.status
            && votesYes == summary.votesYes
            && votesNo == summary.votesNo
            && votesCancelled == summary.votesCancelled
            && threshold == summary.threshold
    }

    init(record: ProposalInspectionProposal) {
        self.init(
            transactionIndex: record.transactionIndex,
            status: record.status,
            votesYes: record.votes.approve,
            votesNo: record.votes.reject,
            votesCancelled: record.votes.cancel,
            threshold: record.threshold,
            kind: record.kind,
            votersYes: record.voters.approve,
            votersNo: record.voters.reject,
            votersCancelled: record.voters.cancel,
            instructions: record.instructions.map(SquadDecodedInstruction.init(record:)),
            accountsReferenced: record.accountsReferenced,
            transactionAddress: record.transactionAddress,
            proposer: record.proposer,
            createdAtUnix: record.createdAtUnix
        )
    }
}

extension SquadDecodedInstruction {
    init(record: ProposalInspectionInstruction) {
        self.init(
            program: record.program,
            kind: record.kind,
            summary: record.summary,
            accounts: record.accounts,
            rawDataHex: record.rawDataHex,
            configAction: record.configAction.map(SquadConfigAction.init(record:))
        )
    }
}

extension SquadConfigAction {
    init(record: ProposalInspectionConfigAction) {
        self.init(
            memberKey: record.memberKey,
            canInitiate: record.canInitiate,
            canVote: record.canVote,
            canExecute: record.canExecute,
            newThreshold: record.newThreshold,
            newTimeLockSeconds: record.newTimeLockSeconds,
            newRentCollector: record.newRentCollector,
            clearsRentCollector: record.clearsRentCollector
        )
    }
}

extension SquadActivityItem {
    init(record: RelayActivityItem) {
        self.init(
            signature: record.signature,
            slot: record.slot,
            timestampUnix: record.timestampUnix,
            kind: record.kind,
            error: record.error,
            action: record.action
        )
    }
}
