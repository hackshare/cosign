extension DemoSquad {
    static func operations(members: DemoMembers) -> DemoSquad {
        OperationsDemoSquad(members: members).make()
    }

    static func operationsReporting(members: DemoMembers) -> DemoSquad {
        DemoPortfolioSquad(
            member: members.member(0),
            address: "OpsReportingSqDAvq79K2x5p7Wqf4eNs6T2mB8cR",
            displayName: "Reporting",
            vaultAddress: "OpsReportingVaultAvq79K2x8f3Qp6nR4zMz",
            transactionIndex: 8,
            nativeBalance: 230_000_000_000
        ).make()
    }

    static func operationsPayroll(members: DemoMembers) -> DemoSquad {
        DemoPortfolioSquad(
            member: members.member(0),
            address: "OpsPayrollSqDAvq79K2x9nV5sLm3pQw6cR2aT",
            displayName: "Payroll",
            vaultAddress: "OpsPayrollVaultAvq79K2x2bN8uJp6eQc",
            transactionIndex: 4,
            nativeBalance: 96_000_000_000
        ).make()
    }

    static func operationsGovernance(members: DemoMembers) -> DemoSquad {
        DemoPortfolioSquad(
            member: members.member(0),
            address: "OpsGovernanceSqDAvq79K2x7jQc4eLm8Tz3rY",
            displayName: "Governance",
            vaultAddress: "OpsGovernanceVaultAvq79K2x4nN7wQp3",
            transactionIndex: 3,
            nativeBalance: 28_000_000_000
        ).make()
    }
}

private struct OperationsDemoSquad {
    let members: DemoMembers

    let squad = "SqDsOPerations9dWfK2qvV7nH8rUxYkC8JmQ4eL2p"
    let vault0 = "Vt2Kp9dA7m9Pe7FgpJtvA3RF5RcjHqYwK8tCrm9Pe"
    let vault1 = "VaU1tTwo92hM4LxPbz9E4Qy7sT3RqKcW15mHc76KyxMW"
    let recipient = "7cNd8mYFmpVKw9X29zQz6w8h1z4Rb82JfP5MxK29"
    let executedSignature = "38Hz4sbUsu5u6wV7hFgGz7xyrRCMK3rQc6GFexyqPQW"

    func make() -> DemoSquad {
        let proposalMap = Dictionary(uniqueKeysWithValues: proposals.map { ($0.transactionIndex, $0) })
        let inspectionMap = Dictionary(uniqueKeysWithValues: proposals.map {
            ($0.transactionIndex, makeDemoProposalInspection(squad: squad, proposal: $0))
        })
        let executed = makeExecutedInspection()

        return DemoSquad(
            summary: summary,
            detail: detail,
            nativeBalances: nativeBalances,
            assets: assets,
            proposals: proposalMap,
            inspections: inspectionMap,
            executedInspections: [executedSignature: executed],
            executionSignatures: [10: executedSignature],
            activity: activityItems(inspections: inspectionMap, executed: executed),
            accountOwners: [
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
            ]
        )
    }

    private var summary: RelaySquadSummary {
        RelaySquadSummary(
            address: squad,
            displayName: "Operations",
            threshold: 3,
            memberCount: UInt32(memberRecords.count),
            transactionIndex: 14,
            staleTransactionIndex: 0
        )
    }

    private var detail: RelaySquadDetail {
        RelaySquadDetail(
            address: squad,
            displayName: "Operations",
            threshold: 3,
            timeLockSeconds: 0,
            transactionIndex: 14,
            staleTransactionIndex: 0,
            members: memberRecords,
            vaults: vaults
        )
    }

    private var memberRecords: [RelaySquadMember] {
        [
            RelaySquadMember(pubkey: members.member(0), canInitiate: true, canVote: true, canExecute: true),
            RelaySquadMember(
                pubkey: "Avq7qVtk9K2xnt9dbM5Xx8GJ2e92wK7cBt56QRx9K2x",
                canInitiate: true,
                canVote: true,
                canExecute: true
            ),
            RelaySquadMember(
                pubkey: "CnW99R2Xpv6e42zL9hRp5KxQp4s8MeD6VwY1qHn8t7F",
                canInitiate: false,
                canVote: true,
                canExecute: false
            )
        ]
    }

    private var vaults: [RelaySquadVaultRef] {
        [
            RelaySquadVaultRef(index: 0, address: vault0),
            RelaySquadVaultRef(index: 1, address: vault1)
        ]
    }

    private var nativeBalances: [String: UInt64] {
        [
            vault0: 842_501_200_000,
            vault1: 442_000_000_000
        ]
    }

    private var proposals: [ProposalInspectionProposal] {
        [
            makeDemoTransferProposal(DemoTransferProposalDraft(
                voting: voting(14, status: "active", approvals: Array(memberApprovals.dropFirst())),
                source: vault0,
                destination: recipient,
                amount: "250 SOL",
                program: "System Program",
                rawDataHex: "02000000"
            )),
            makeDemoTransferProposal(DemoTransferProposalDraft(
                voting: voting(13, status: "approved", approvals: memberApprovals),
                source: vault0,
                destination: recipient,
                amount: "120,000 USDC",
                program: "SPL Token Program",
                rawDataHex: "03000000"
            )),
            makeDemoConfigProposal(
                voting: voting(12, status: "executed", approvals: memberApprovals),
                squad: squad
            ),
            makeDemoUnknownProposal(voting(11, status: "active", approvals: [])),
            makeDemoTransferProposal(DemoTransferProposalDraft(
                voting: voting(10, status: "executed", approvals: memberApprovals),
                source: vault1,
                destination: recipient,
                amount: "50 SOL",
                program: "System Program",
                rawDataHex: "02000000"
            ))
        ]
    }

    private var memberApprovals: [String] {
        memberRecords.map(\.pubkey)
    }

    private var assets: [String: [DASAsset]] {
        [
            vault0: [
                makeDemoToken(DemoTokenAsset(
                    id: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                    symbol: "USDC",
                    name: "USD Coin",
                    amount: "84300000000",
                    display: "84,300",
                    decimals: 6
                )),
                makeDemoToken(DemoTokenAsset(
                    id: "jtojtomepa8beP8AuQc6eXt5FriJwfFMwQx2v2f9mCL",
                    symbol: "JTO",
                    name: "JITO",
                    amount: "1420000000000",
                    display: "1,420",
                    decimals: 9
                )),
                makeDemoToken(DemoTokenAsset(
                    id: "98sMhvDwXj1RQi5c5Mndm3vPe9cBqPrbLaufMXFNMh5g",
                    symbol: "HYPE",
                    name: "HYPE",
                    amount: "360000000000",
                    display: "360",
                    decimals: 9
                ))
            ],
            vault1: [
                makeDemoToken(DemoTokenAsset(
                    id: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                    symbol: "USDC",
                    name: "USD Coin",
                    amount: "42600000000",
                    display: "42,600",
                    decimals: 6
                )),
                makeDemoToken(DemoTokenAsset(
                    id: "hntyVP6YFm1Hg25TN9WGLqM12b8TQmcknKrdu1oxWux",
                    symbol: "HNT",
                    name: "Helium Network Token",
                    amount: "1240000000000",
                    display: "12,400",
                    decimals: 8
                )),
                makeDemoToken(DemoTokenAsset(
                    id: "UnkNownMint9mPe7FgpJtvA3RF5RcjHqYwK8t",
                    symbol: nil,
                    name: "Unknown mint",
                    amount: "1000000000",
                    display: "1,000",
                    decimals: 6,
                    token2022: true
                ))
            ]
        ]
    }

    private func makeExecutedInspection() -> ExecutedTransactionInspectionReport {
        makeDemoExecutedInspection(
            signature: executedSignature,
            slot: 76565,
            blockTime: 1_779_230_000,
            action: makeDemoAction(
                classification: "sol_transfer",
                summary: "Sent 50 SOL",
                confidence: "decoded",
                effect: RelayInspectionEffect(
                    kind: "transfer",
                    summary: "Transfer 50 SOL to \(shortDemoAddress(recipient))",
                    program: "System Program",
                    asset: "SOL",
                    amount: "50 SOL",
                    source: vault1,
                    destination: recipient
                )
            )
        )
    }

    private func activityItems(
        inspections: [UInt64: ProposalInspectionReport],
        executed: ExecutedTransactionInspectionReport
    ) -> [RelayActivityItem] {
        [
            makeDemoActivity(signature: executedSignature, slot: 76565, kind: "execute", action: executed.action),
            makeDemoActivity(
                signature: "5wQp2xM5DemoApproveOperations13nF5s88pQs",
                slot: 76510,
                kind: "approve",
                action: inspections[13]?.action
            ),
            makeDemoActivity(
                signature: "4nq2z4KDemoCreateOperations14xY3p8QmS7p",
                slot: 76420,
                kind: "create",
                action: inspections[14]?.action
            )
        ]
    }

    private func voting(
        _ index: UInt64,
        status: String,
        approvals: [String]
    ) -> DemoProposalVoting {
        DemoProposalVoting(
            index: index,
            status: status,
            threshold: 3,
            approvals: approvals,
            transactionAddress: transactionAccount(index)
        )
    }

    private func transactionAccount(_ index: UInt64) -> String {
        switch index {
        case 14:
            "Tx14OPerationsQG5LqMKv5kmgV7pS9wYudGx9F"
        case 13:
            "Tx13OPerationsQG5LqMKv5kmgV7pS9wYudGx9F"
        case 12:
            "Tx12OPerationsQG5LqMKv5kmgV7pS9wYudGx9F"
        case 11:
            "Tx11UnknownProgram9vV7nH8rUxYkC8JmQ4eL2p"
        default:
            "Tx10ExecutedSolTransfer5LqMKv5kmgV7pS9wYudGx"
        }
    }
}
