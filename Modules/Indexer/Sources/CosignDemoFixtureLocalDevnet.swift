extension DemoSquad {
    static func localDevnet(members: DemoMembers) -> DemoSquad {
        LocalDevnetDemoSquad(members: members).make()
    }
}

private struct LocalDevnetDemoSquad {
    let members: DemoMembers

    private let squad = "LocalDevnetSqD4HxndWs1R6a9qPe7FgT3rUx"
    private let vault = "LocalDevnetVault4HxndWs1Pe7FgpJtvA3R"

    func make() -> DemoSquad {
        let proposal = makeDemoMemoProposal(voting)
        let inspection = makeDemoProposalInspection(squad: squad, proposal: proposal)

        return DemoSquad(
            summary: RelaySquadSummary(
                address: squad,
                displayName: "Local devnet",
                threshold: 1,
                memberCount: 1,
                transactionIndex: 1,
                staleTransactionIndex: 0
            ),
            detail: RelaySquadDetail(
                address: squad,
                displayName: "Local devnet",
                threshold: 1,
                timeLockSeconds: 0,
                transactionIndex: 1,
                staleTransactionIndex: 0,
                members: [
                    RelaySquadMember(pubkey: members.member(2), canInitiate: true, canVote: true, canExecute: true)
                ],
                vaults: [
                    RelaySquadVaultRef(index: 0, address: vault)
                ]
            ),
            nativeBalances: [vault: 6_000_000_000],
            assets: [vault: []],
            proposals: [proposal.transactionIndex: proposal],
            inspections: [proposal.transactionIndex: inspection],
            executedInspections: [:],
            executionSignatures: [:],
            activity: [
                makeDemoActivity(
                    signature: "4HxnDemoLocalDevnetCreate1dWs1Qp",
                    slot: 76340,
                    kind: "create",
                    action: inspection.action
                )
            ]
        )
    }

    private var voting: DemoProposalVoting {
        DemoProposalVoting(
            index: 1,
            status: "active",
            threshold: 1,
            approvals: [],
            transactionAddress: "Tx01LocalDevnet4HxndWs1Pe7FgpJtvA3R"
        )
    }
}
