struct DemoMembers {
    let addresses: [String]

    func member(_ index: Int) -> String {
        if addresses.indices.contains(index) {
            return addresses[index]
        }
        return fallbackMembers[index % fallbackMembers.count]
    }

    private let fallbackMembers = [
        "mAVb1zcD7NAKYpm5PXpSmpDttCUTu9Af248fnpBLqQA",
        "Avq7qVtk9K2xnt9dbM5Xx8GJ2e92wK7cBt56QRx9K2x",
        "BkR3kP6t7nQpY5e2QWc63RZ2zJE94YV8bMGGLLN7nQp"
    ]
}

struct DemoSquad {
    let summary: RelaySquadSummary
    let detail: RelaySquadDetail
    let nativeBalances: [String: UInt64]
    let assets: [String: [DASAsset]]
    let proposals: [UInt64: ProposalInspectionProposal]
    let inspections: [UInt64: ProposalInspectionReport]
    let executedInspections: [String: ExecutedTransactionInspectionReport]
    let executionSignatures: [UInt64: String]
    let activity: [RelayActivityItem]
    var accountOwners: [String: String] = [:]
}

struct DemoProposalVoting {
    let index: UInt64
    let status: String
    let threshold: UInt16
    let approvals: [String]
    let transactionAddress: String
}

struct DemoProposalDraft {
    let voting: DemoProposalVoting
    let kind: String
    let accounts: [String]
    let instructions: [ProposalInspectionInstruction]
}

struct DemoTransferProposalDraft {
    let voting: DemoProposalVoting
    let source: String
    let destination: String
    let amount: String
    let program: String
    let rawDataHex: String
}

struct DemoTokenAsset {
    let id: String
    let symbol: String?
    let name: String
    let amount: String
    let display: String
    let decimals: UInt8
    var token2022 = false
}
