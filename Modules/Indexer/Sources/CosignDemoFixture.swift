import Foundation

// SAFETY: holds only immutable demo data (`let cluster`, `let squads`), never mutated
// after init.
public final class CosignDemoFixture: @unchecked Sendable {
    private let cluster = "demo"
    private let squads: [DemoSquad]

    private init(squads: [DemoSquad]) {
        self.squads = squads
    }

    public func accountOwner(address: String) -> String? {
        squads.compactMap { $0.accountOwners[address] }.first
    }

    public func memberSquads(for request: MemberSquadsRequest) throws -> MemberSquadsResponse {
        let matchingSquads = squads.filter { squad in
            squad.detail.members.contains { $0.pubkey == request.memberAddress }
        }

        return MemberSquadsResponse(
            kind: "member_squads",
            member: request.memberAddress,
            cluster: cluster,
            squads: matchingSquads.map(\.summary)
        )
    }

    public func squadDetail(for request: SquadDetailRequest) throws -> SquadDetailResponse {
        let squad = try squad(address: request.squadAddress)
        return SquadDetailResponse(kind: "squad_detail", cluster: cluster, squad: squad.detail)
    }

    public func squadProposals(for request: SquadProposalsRequest) throws -> SquadProposalsResponse {
        let squad = try squad(address: request.squadAddress)
        let proposals = squad.proposals.values
            .filter { request.fromIndex ... request.toIndex ~= $0.transactionIndex }
            .sorted { $0.transactionIndex > $1.transactionIndex }
            .map { proposal in
                RelayProposalSummary(
                    transactionIndex: proposal.transactionIndex,
                    status: proposal.status,
                    votesYes: proposal.votes.approve,
                    votesNo: proposal.votes.reject,
                    votesCancelled: proposal.votes.cancel,
                    threshold: proposal.threshold,
                    kind: proposal.kind,
                    action: squad.inspections[proposal.transactionIndex]?.action
                )
            }

        return SquadProposalsResponse(
            kind: "squad_proposals",
            squad: request.squadAddress,
            cluster: cluster,
            range: RelayProposalRange(fromIndex: request.fromIndex, toIndex: request.toIndex),
            proposals: proposals
        )
    }

    public func squadProposal(for request: SquadProposalRequest) throws -> SquadProposalResponse {
        let squad = try squad(address: request.squadAddress)
        guard let proposal = squad.proposals[request.transactionIndex] else {
            throw RelayClientError.httpStatus(404, message: "Demo proposal not found.")
        }

        return SquadProposalResponse(
            kind: "squad_proposal",
            squad: request.squadAddress,
            cluster: cluster,
            proposal: proposal
        )
    }

    public func accountActivity(for request: AccountActivityRequest) throws -> AccountActivityResponse {
        let activity = activityItems(for: request.address)
        let limitedActivity = Array(activity.prefix(Int(request.limit)))

        return AccountActivityResponse(
            kind: "account_activity",
            address: request.address,
            cluster: cluster,
            before: request.beforeSignature,
            limit: request.limit,
            activity: limitedActivity
        )
    }

    public func transactionStatus(for request: TransactionStatusRequest) throws -> TransactionStatusResponse {
        guard let executed = executedInspection(signature: request.signature) else {
            throw RelayClientError.httpStatus(404, message: "Demo transaction not found.")
        }

        return TransactionStatusResponse(
            kind: "transaction_status",
            signature: request.signature,
            cluster: cluster,
            status: RelayTransactionStatus(
                slot: executed.status.slot,
                status: executed.status.status,
                error: executed.status.error
            )
        )
    }

    public func proposalInspectionReport(for request: ProposalInspectionRequest) throws -> ProposalInspectionReport {
        let squad = try squad(address: request.squadAddress)
        guard let report = squad.inspections[request.transactionIndex] else {
            throw RelayClientError.httpStatus(404, message: "Demo inspection not found.")
        }
        return report
    }

    public func executedTransactionInspectionReport(
        for request: ExecutedTransactionInspectionRequest
    ) throws -> ExecutedTransactionInspectionReport {
        guard let report = executedInspection(signature: request.signature) else {
            throw RelayClientError.httpStatus(404, message: "Demo executed transaction not found.")
        }
        return report
    }

    public func nativeBalanceLamports(for vaultAddress: String) -> UInt64? {
        squads.first { $0.nativeBalances[vaultAddress] != nil }?.nativeBalances[vaultAddress]
    }

    public func assets(for vaultAddress: String) -> [DASAsset]? {
        squads.first { $0.assets[vaultAddress] != nil }?.assets[vaultAddress]
    }

    public func executionSignature(in squadAddress: String, transactionIndex: UInt64) -> String? {
        try? squad(address: squadAddress).executionSignatures[transactionIndex]
    }

    private func squad(address: String) throws -> DemoSquad {
        guard let squad = squads.first(where: { $0.summary.address == address }) else {
            throw RelayClientError.httpStatus(404, message: "Demo Squad not found.")
        }
        return squad
    }

    private func activityItems(for address: String) -> [RelayActivityItem] {
        if let squad = squads.first(where: { $0.summary.address == address }) {
            return squad.activity
        }

        for squad in squads {
            if let signature = squad.executionSignatures.first(where: { _, signature in
                squad.proposals.values.contains { $0.transactionAddress == address } && !signature.isEmpty
            })?.value, let executed = squad.executedInspections[signature] {
                return [
                    RelayActivityItem(
                        signature: executed.signature,
                        slot: executed.status.slot ?? 0,
                        timestampUnix: executed.status.blockTime ?? 1_799_000_000,
                        kind: "execute",
                        error: executed.status.error,
                        action: executed.action
                    )
                ]
            }
        }

        return squads.flatMap(\.activity).filter { item in
            item.action?.effects.contains { effect in
                effect.source == address || effect.destination == address
            } == true
        }
    }

    private func executedInspection(signature: String) -> ExecutedTransactionInspectionReport? {
        if let report = squads.compactMap({ $0.executedInspections[signature] }).first {
            return report
        }
        return demoSubmittedInspection(signature: signature)
    }

    private func demoSubmittedInspection(signature: String) -> ExecutedTransactionInspectionReport? {
        guard let submitted = CosignDemoSubmissionSignature.parse(signature) else {
            return nil
        }

        for squad in squads {
            guard let proposal = squad.proposals[submitted.proposalIndex] else {
                continue
            }
            return makeDemoExecutedInspection(
                signature: signature,
                slot: 90000 + submitted.proposalIndex * 10 + UInt64(submitted.offset),
                blockTime: 1_779_240_000 + Int64(submitted.proposalIndex),
                action: demoSubmittedAction(submitted, proposal: proposal, squad: squad)
            )
        }

        return nil
    }

    private func demoSubmittedAction(
        _ submitted: CosignDemoSubmissionSignature,
        proposal: ProposalInspectionProposal,
        squad: DemoSquad
    ) -> RelayInspectionAction {
        switch submitted.kind {
        case .propose:
            makeDemoSquadsAction(
                classification: "squads_create_proposal",
                summary: "Create proposal #\(proposal.transactionIndex)",
                effectKind: "proposal_creation",
                proposal: proposal
            )
        case .execute, .approveAndExecute:
            squad.inspections[submitted.proposalIndex]?.action ?? makeDemoAction(for: proposal)
        case .approve:
            makeDemoSquadsAction(
                classification: "squads_approve",
                summary: "Approve proposal #\(proposal.transactionIndex)",
                effectKind: "approval",
                proposal: proposal
            )
        case .reject:
            makeDemoSquadsAction(
                classification: "squads_reject",
                summary: "Reject proposal #\(proposal.transactionIndex)",
                effectKind: "rejection",
                proposal: proposal
            )
        case .cancel:
            makeDemoSquadsAction(
                classification: "squads_cancel",
                summary: "Cancel proposal #\(proposal.transactionIndex)",
                effectKind: "cancellation",
                proposal: proposal
            )
        }
    }

    private func makeDemoSquadsAction(
        classification: String,
        summary: String,
        effectKind: String,
        proposal: ProposalInspectionProposal
    ) -> RelayInspectionAction {
        makeDemoAction(
            classification: classification,
            summary: summary,
            confidence: "decoded",
            effect: RelayInspectionEffect(
                kind: effectKind,
                summary: summary,
                program: "Squads",
                asset: nil,
                amount: nil,
                source: proposal.voters.approve.first,
                destination: proposal.transactionAddress
            )
        )
    }
}

public extension CosignDemoFixture {
    static func appStore(memberAddresses: [String]) -> CosignDemoFixture {
        let members = DemoMembers(addresses: memberAddresses)
        return CosignDemoFixture(squads: [
            DemoSquad.operations(members: members),
            DemoSquad.operationsReporting(members: members),
            DemoSquad.operationsPayroll(members: members),
            DemoSquad.operationsGovernance(members: members),
            DemoSquad.treasury(members: members),
            DemoSquad.treasuryReserve(members: members),
            DemoSquad.localDevnet(members: members)
        ])
    }

    static func profile(_ profile: String, memberAddresses: [String]) -> CosignDemoFixture {
        switch profile.lowercased() {
        case "nosigners":
            CosignDemoFixture(squads: [])
        case "nullstates":
            nullStates(memberAddresses: memberAddresses)
        default:
            appStore(memberAddresses: memberAddresses)
        }
    }

    static func nullStates(memberAddresses: [String]) -> CosignDemoFixture {
        let members = DemoMembers(addresses: memberAddresses)
        return CosignDemoFixture(squads: [
            DemoSquad.emptyPortfolio(members: members),
            DemoSquad.noVaults(members: members)
        ])
    }
}
