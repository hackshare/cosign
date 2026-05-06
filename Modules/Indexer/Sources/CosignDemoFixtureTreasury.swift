extension DemoSquad {
    static func treasury(members: DemoMembers) -> DemoSquad {
        TreasuryDemoSquad(members: members).make()
    }

    static func treasuryReserve(members: DemoMembers) -> DemoSquad {
        DemoPortfolioSquad(
            member: members.member(1),
            address: "TreasuryReserveSqDBkR37nQp5cV8rUxYK2mH4",
            displayName: "Reserve",
            vaultAddress: "TreasuryReserveVaultBkR37nQp9cV8rUx",
            transactionIndex: 2,
            nativeBalance: 72_000_000_000
        ).make()
    }
}

private struct TreasuryDemoSquad {
    let members: DemoMembers

    let squad = "TrEaSurySquadBkR37nQp9dWfK2qvV7nH8rUxYK"
    let vault = "TrEaSuryVault01BkR37nQp9dWfK2qvV7nH8rUxYK"
    let recipient = "9abcDemoRecipientBkR37nQp9dWfK2qvV7nH8rUxYK"
    let executedSignature = "4wfQgP4e8n8AVpFcaoq7UvYUCKB5qMeawmoyiKEYZdL"
    let executedSignatureIDL = "6kTpRr2DemoTreasuryIdlExec8n8AVpFcaoq7UvYUCKB5q"

    func make() -> DemoSquad {
        let proposalMap = Dictionary(uniqueKeysWithValues: proposals.map { ($0.transactionIndex, $0) })
        let confidenceOverrides: [UInt64: String] = [6: "idl", 5: "partial"]
        let inspectionMap = Dictionary(uniqueKeysWithValues: proposals.map {
            (
                $0.transactionIndex,
                makeDemoProposalInspection(
                    squad: squad,
                    proposal: $0,
                    confidence: confidenceOverrides[$0.transactionIndex]
                )
            )
        })
        let executed = makeDemoExecutedInspection(
            signature: executedSignature,
            slot: 77104,
            blockTime: 1_779_235_600,
            action: inspectionMap[5]?.action ?? fallbackExecutedAction
        )
        let executedIDL = makeDemoExecutedInspection(
            signature: executedSignatureIDL,
            slot: 77055,
            blockTime: 1_779_235_400,
            action: inspectionMap[6]?.action ?? fallbackExecutedAction
        )

        return DemoSquad(
            summary: summary,
            detail: detail,
            nativeBalances: [vault: 128_450_000_000],
            assets: assets,
            proposals: proposalMap,
            inspections: inspectionMap,
            executedInspections: [executedSignature: executed, executedSignatureIDL: executedIDL],
            executionSignatures: [5: executedSignature, 6: executedSignatureIDL],
            activity: activityItems(inspections: inspectionMap, executed: executed)
        )
    }

    private var summary: RelaySquadSummary {
        RelaySquadSummary(
            address: squad,
            displayName: "Treasury",
            threshold: 1,
            memberCount: UInt32(memberRecords.count),
            transactionIndex: 6,
            staleTransactionIndex: 0
        )
    }

    private var detail: RelaySquadDetail {
        RelaySquadDetail(
            address: squad,
            displayName: "Treasury",
            threshold: 1,
            timeLockSeconds: 0,
            transactionIndex: 6,
            staleTransactionIndex: 0,
            members: memberRecords,
            vaults: [RelaySquadVaultRef(index: 0, address: vault)]
        )
    }

    private var memberRecords: [RelaySquadMember] {
        [
            RelaySquadMember(pubkey: members.member(1), canInitiate: true, canVote: true, canExecute: true),
            RelaySquadMember(
                pubkey: "Dx4P7h7RbBkR37nQp9dWfK2qvV7nH8rUxY",
                canInitiate: true,
                canVote: true,
                canExecute: true
            )
        ]
    }

    private var proposals: [ProposalInspectionProposal] {
        [
            makeDemoTransferProposal(DemoTransferProposalDraft(
                voting: voting(6, status: "executed", approvals: [members.member(1)]),
                source: vault,
                destination: recipient,
                amount: "18,000 USDC",
                program: "SPL Token Program",
                rawDataHex: "03000000"
            )),
            makeDemoTransferProposal(DemoTransferProposalDraft(
                voting: voting(5, status: "executed", approvals: [members.member(1)]),
                source: vault,
                destination: recipient,
                amount: "4 JTO",
                program: "SPL Token Program",
                rawDataHex: "03000000"
            ))
        ]
    }

    private var assets: [String: [DASAsset]] {
        [
            vault: [
                makeDemoToken(DemoTokenAsset(
                    id: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                    symbol: "USDC",
                    name: "USD Coin",
                    amount: "22000000000",
                    display: "22,000",
                    decimals: 6
                )),
                makeDemoToken(DemoTokenAsset(
                    id: "jtojtomepa8beP8AuQc6eXt5FriJwfFMwQx2v2f9mCL",
                    symbol: "JTO",
                    name: "JITO",
                    amount: "950000000000",
                    display: "950",
                    decimals: 9
                ))
            ]
        ]
    }

    private var fallbackExecutedAction: RelayInspectionAction {
        makeDemoAction(
            classification: "token_transfer",
            summary: "Transferred 4 JTO",
            confidence: "decoded",
            effect: RelayInspectionEffect(
                kind: "transfer",
                summary: "Transfer 4 JTO",
                program: "SPL Token Program",
                asset: "JTO",
                amount: "4",
                source: vault,
                destination: recipient
            )
        )
    }

    private func activityItems(
        inspections: [UInt64: ProposalInspectionReport],
        executed: ExecutedTransactionInspectionReport
    ) -> [RelayActivityItem] {
        [
            makeDemoActivity(signature: executedSignature, slot: 77104, kind: "execute", action: executed.action),
            makeDemoActivity(
                signature: "2axNoL6DemoTreasuryMemo6hrrTAX",
                slot: 77055,
                kind: "approve",
                action: inspections[6]?.action
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
            threshold: 1,
            approvals: approvals,
            transactionAddress: transactionAccount(index)
        )
    }

    private func transactionAccount(_ index: UInt64) -> String {
        switch index {
        case 6:
            "Tx06TreasuryMemoBkR37nQp9dWfK2qvV7nH8rUxYK"
        default:
            "Tx05TreasuryTokenBkR37nQp9dWfK2qvV7nH8rUxYK"
        }
    }
}
