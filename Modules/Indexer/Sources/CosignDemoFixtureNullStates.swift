extension DemoSquad {
    static func emptyPortfolio(members: DemoMembers) -> DemoSquad {
        EmptyPortfolioDemoSquad(members: members).make()
    }

    static func noVaults(members: DemoMembers) -> DemoSquad {
        NoVaultsDemoSquad(members: members).make()
    }
}

private struct EmptyPortfolioDemoSquad {
    let members: DemoMembers

    let squad = "Nu11EmptyPortfolio9dWfK2qvV7nH8rUxYkC8JmQ"
    let vault = "Nu11EmptyVault9dWfK2qvV7nH8rUxYkC8JmQ4eL2p"

    func make() -> DemoSquad {
        DemoSquad(
            summary: RelaySquadSummary(
                address: squad,
                displayName: "Empty portfolio",
                threshold: 1,
                memberCount: UInt32(memberRecords.count),
                transactionIndex: 0,
                staleTransactionIndex: 0
            ),
            detail: RelaySquadDetail(
                address: squad,
                displayName: "Empty portfolio",
                threshold: 1,
                timeLockSeconds: 0,
                transactionIndex: 0,
                staleTransactionIndex: 0,
                members: memberRecords,
                vaults: [RelaySquadVaultRef(index: 0, address: vault)]
            ),
            nativeBalances: [vault: 0],
            assets: [vault: []],
            proposals: [:],
            inspections: [:],
            executedInspections: [:],
            executionSignatures: [:],
            activity: []
        )
    }

    private var memberRecords: [RelaySquadMember] {
        [
            RelaySquadMember(pubkey: members.member(0), canInitiate: true, canVote: true, canExecute: true)
        ]
    }
}

private struct NoVaultsDemoSquad {
    let members: DemoMembers

    let squad = "Nu11NoVaults9dWfK2qvV7nH8rUxYkC8JmQ4eL2p"

    func make() -> DemoSquad {
        DemoSquad(
            summary: RelaySquadSummary(
                address: squad,
                displayName: "No-vault Squad",
                threshold: 2,
                memberCount: UInt32(memberRecords.count),
                transactionIndex: 0,
                staleTransactionIndex: 0
            ),
            detail: RelaySquadDetail(
                address: squad,
                displayName: "No-vault Squad",
                threshold: 2,
                timeLockSeconds: 0,
                transactionIndex: 0,
                staleTransactionIndex: 0,
                members: memberRecords,
                vaults: []
            ),
            nativeBalances: [:],
            assets: [:],
            proposals: [:],
            inspections: [:],
            executedInspections: [:],
            executionSignatures: [:],
            activity: []
        )
    }

    private var memberRecords: [RelaySquadMember] {
        [
            RelaySquadMember(pubkey: members.member(1), canInitiate: false, canVote: true, canExecute: false),
            RelaySquadMember(pubkey: members.member(0), canInitiate: true, canVote: true, canExecute: true)
        ]
    }
}
