import Indexer
import Testing
@testable import Squads

struct SquadsViewModelTests {
    @Test func proposalRangeIsHashable() {
        let ranges: Set<ProposalRange> = [
            ProposalRange(fromIndex: 1, toIndex: 10),
            ProposalRange(fromIndex: 1, toIndex: 10),
            ProposalRange(fromIndex: 11, toIndex: 20)
        ]

        #expect(ranges.count == 2)
    }

    @Test func recentProposalRangeUsesOneBasedTransactionIndices() throws {
        let range = try #require(ProposalRange.recent(through: 7, limit: 5))

        #expect(range.fromIndex == 3)
        #expect(range.toIndex == 7)
    }

    @Test func recentProposalRangeStartsAtOneWhenLimitExceedsHistory() throws {
        let range = try #require(ProposalRange.recent(through: 3, limit: 50))

        #expect(range.fromIndex == 1)
        #expect(range.toIndex == 3)
    }

    @Test func recentProposalRangeIsNilWithoutHistory() {
        #expect(ProposalRange.recent(through: 0) == nil)
        #expect(ProposalRange.recent(through: 10, limit: 0) == nil)
    }

    @Test func vaultDetailIdentityUsesVaultIndex() {
        let ref = SquadVaultRef(index: 2, address: "vault-address")
        let detail = VaultDetail(ref: ref, nativeBalanceLamports: 42, assets: [])

        #expect(ref.id == 2)
        #expect(detail.id == 2)
    }

    @Test func proposalDetailCarriesDecodedInstructions() {
        let instruction = SquadDecodedInstruction(
            program: "System Program",
            kind: "transfer",
            summary: "Transfer SOL",
            rawDataHex: "02000000"
        )
        let detail = SquadProposalDetail(
            transactionIndex: 12,
            status: "active",
            votesYes: 1,
            votesNo: 0,
            votesCancelled: 0,
            threshold: 2,
            kind: "vault_transaction",
            votersYes: ["member-a"],
            votersNo: [],
            votersCancelled: [],
            instructions: [instruction],
            accountsReferenced: ["member-a"],
            transactionAddress: "transaction-account"
        )

        #expect(detail.id == 12)
        #expect(detail.instructions == [instruction])
        #expect(detail.transactionAddress == "transaction-account")
    }

    @Test func activeProposalAllowsVotingMemberActions() {
        let proposal = makeProposal(status: "active")
        let member = makeMember(canVote: true, canExecute: false)

        #expect(availableProposalActions(for: proposal, member: member) == [.approve, .reject])
    }

    @Test func activeProposalOffersApproveAndExecuteForFinalApproval() {
        let proposal = makeProposal(status: "active", votersYes: ["member-b"], threshold: 2)
        let member = makeMember(canVote: true, canExecute: true)

        #expect(
            availableProposalActions(for: proposal, member: member) ==
                [.approve, .approveAndExecute, .reject]
        )
    }

    @Test func activeProposalHidesApproveAndExecuteBeforeFinalApproval() {
        let proposal = makeProposal(status: "active", votersYes: ["member-b"], threshold: 3)
        let member = makeMember(canVote: true, canExecute: true)

        #expect(availableProposalActions(for: proposal, member: member) == [.approve, .reject])
    }

    @Test func activeProposalRequiresExecutePermissionForApproveAndExecute() {
        let proposal = makeProposal(status: "active", votersYes: ["member-b"], threshold: 2)
        let member = makeMember(canVote: true, canExecute: false)

        #expect(availableProposalActions(for: proposal, member: member) == [.approve, .reject])
    }

    @Test func activeProposalHidesActionsAfterSignerVotes() {
        let proposal = makeProposal(status: "active", votersYes: ["member-a"])
        let member = makeMember(canVote: true, canExecute: true)

        #expect(availableProposalActions(for: proposal, member: member).isEmpty)
        #expect(proposalActionUnavailableMessage(for: proposal, member: member) ==
            "The selected signer already approved this proposal.")
    }

    @Test func approvedProposalSeparatesExecuteAndCancelPermissions() {
        let proposal = makeProposal(status: "approved")

        #expect(availableProposalActions(
            for: proposal,
            member: makeMember(canVote: false, canExecute: true)
        ) == [.execute])
        #expect(availableProposalActions(
            for: proposal,
            member: makeMember(canVote: true, canExecute: false)
        ) == [.cancel])
    }

    @Test func proposalDetailMatchesSummaryForSigningInvariant() {
        let proposal = makeProposal(status: "active", votersYes: ["member-a"], threshold: 2)

        #expect(proposal.matches(makeSummary(from: proposal)))
        #expect(!proposal.matches(makeSummary(from: proposal, transactionIndex: 3)))
        #expect(!proposal.matches(makeSummary(from: proposal, status: "approved")))
        #expect(!proposal.matches(makeSummary(from: proposal, votesYes: 2)))
        #expect(!proposal.matches(makeSummary(from: proposal, votesNo: 1)))
        #expect(!proposal.matches(makeSummary(from: proposal, votesCancelled: 1)))
        #expect(!proposal.matches(makeSummary(from: proposal, threshold: 3)))
    }

    @Test func proposalChangedErrorPromptsReview() {
        let proposal = makeProposal(status: "approved")
        let error = ProposalActionError.proposalChanged(makeSummary(from: proposal))

        #expect(error
            .localizedDescription == "The proposal changed before signing. Review the latest state and try again.")
    }

    @Test func displayAmountParserUsesTokenDecimals() {
        #expect(DisplayAmountParser.baseUnits(from: "1.5", decimals: 6) == 1_500_000)
        #expect(DisplayAmountParser.baseUnits(from: "250", decimals: 0) == 250)
        #expect(DisplayAmountParser.baseUnits(from: "250.1", decimals: 0) == nil)
        #expect(DisplayAmountParser.baseUnits(from: "0.000001", decimals: 6) == 1)
        #expect(DisplayAmountParser.baseUnits(from: "0.0000001", decimals: 6) == nil)
    }
}

private func makeMember(
    pubkey: String = "member-a",
    canVote: Bool,
    canExecute: Bool
) -> SquadMember {
    SquadMember(
        pubkey: pubkey,
        canInitiate: false,
        canVote: canVote,
        canExecute: canExecute
    )
}

private func makeProposal(
    status: String,
    votersYes: [String] = [],
    votersNo: [String] = [],
    votersCancelled: [String] = [],
    threshold: UInt16 = 1
) -> SquadProposalDetail {
    SquadProposalDetail(
        transactionIndex: 2,
        status: status,
        votesYes: UInt32(votersYes.count),
        votesNo: UInt32(votersNo.count),
        votesCancelled: UInt32(votersCancelled.count),
        threshold: threshold,
        kind: "vault",
        votersYes: votersYes,
        votersNo: votersNo,
        votersCancelled: votersCancelled,
        instructions: [],
        accountsReferenced: [],
        transactionAddress: "transaction-account"
    )
}

private func makeSummary(
    from proposal: SquadProposalDetail,
    transactionIndex: UInt64? = nil,
    status: String? = nil,
    votesYes: UInt32? = nil,
    votesNo: UInt32? = nil,
    votesCancelled: UInt32? = nil,
    threshold: UInt16? = nil
) -> SquadProposalSummary {
    SquadProposalSummary(
        transactionIndex: transactionIndex ?? proposal.transactionIndex,
        status: status ?? proposal.status,
        votesYes: votesYes ?? proposal.votesYes,
        votesNo: votesNo ?? proposal.votesNo,
        votesCancelled: votesCancelled ?? proposal.votesCancelled,
        threshold: threshold ?? proposal.threshold
    )
}
