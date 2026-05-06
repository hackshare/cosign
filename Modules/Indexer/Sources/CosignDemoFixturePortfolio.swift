struct DemoPortfolioSquad {
    let member: String
    let address: String
    let displayName: String
    let vaultAddress: String
    let transactionIndex: UInt64
    let nativeBalance: UInt64

    func make() -> DemoSquad {
        DemoSquad(
            summary: RelaySquadSummary(
                address: address,
                displayName: displayName,
                threshold: 1,
                memberCount: 1,
                transactionIndex: transactionIndex,
                staleTransactionIndex: 0
            ),
            detail: RelaySquadDetail(
                address: address,
                displayName: displayName,
                threshold: 1,
                timeLockSeconds: 0,
                transactionIndex: transactionIndex,
                staleTransactionIndex: 0,
                members: [
                    RelaySquadMember(pubkey: member, canInitiate: true, canVote: true, canExecute: true)
                ],
                vaults: [
                    RelaySquadVaultRef(index: 0, address: vaultAddress)
                ]
            ),
            nativeBalances: [vaultAddress: nativeBalance],
            assets: [vaultAddress: []],
            proposals: [:],
            inspections: [:],
            executedInspections: [:],
            executionSignatures: [:],
            activity: []
        )
    }
}
