import Foundation

func makeDemoTransferProposal(_ draft: DemoTransferProposalDraft) -> ProposalInspectionProposal {
    makeDemoProposal(DemoProposalDraft(
        voting: draft.voting,
        kind: "vault",
        accounts: [draft.source, draft.destination],
        instructions: [
            ProposalInspectionInstruction(
                program: draft.program,
                kind: "transfer",
                summary: "Transfer \(draft.amount)",
                accounts: [draft.source, draft.destination],
                rawDataHex: draft.rawDataHex
            )
        ]
    ))
}

func makeDemoConfigProposal(
    voting: DemoProposalVoting,
    squad: String
) -> ProposalInspectionProposal {
    makeDemoProposal(DemoProposalDraft(
        voting: voting,
        kind: "config",
        accounts: [squad],
        instructions: [
            ProposalInspectionInstruction(
                program: "Squads",
                kind: "set_threshold",
                summary: "Update threshold to 3 of 3",
                accounts: [squad],
                rawDataHex: "0a000000"
            )
        ]
    ))
}

func makeDemoMemoProposal(_ voting: DemoProposalVoting) -> ProposalInspectionProposal {
    makeDemoProposal(DemoProposalDraft(
        voting: voting,
        kind: "vault",
        accounts: [],
        instructions: [
            ProposalInspectionInstruction(
                program: "Memo Program",
                kind: "memo",
                summary: "Memo: Unknown fixture \(voting.index)",
                accounts: [],
                rawDataHex: "48656c6c6f"
            )
        ]
    ))
}

func makeDemoUnknownProposal(_ voting: DemoProposalVoting) -> ProposalInspectionProposal {
    let unknownProgram = "UnkNownProgram111111111111111111111111111111"
    return makeDemoProposal(DemoProposalDraft(
        voting: voting,
        kind: "vault",
        accounts: [unknownProgram],
        instructions: [
            ProposalInspectionInstruction(
                program: "Unknown Program",
                kind: "raw",
                summary: "Instruction for unknown program",
                accounts: [unknownProgram],
                rawDataHex: "ff00aa55"
            )
        ]
    ))
}

func makeDemoProposal(_ draft: DemoProposalDraft) -> ProposalInspectionProposal {
    ProposalInspectionProposal(
        transactionIndex: draft.voting.index,
        status: draft.voting.status,
        kind: draft.kind,
        threshold: draft.voting.threshold,
        votes: ProposalInspectionVotes(approve: UInt32(draft.voting.approvals.count), reject: 0, cancel: 0),
        voters: ProposalInspectionVoters(approve: draft.voting.approvals, reject: [], cancel: []),
        transactionAddress: draft.voting.transactionAddress,
        accountsReferenced: draft.accounts,
        instructions: draft.instructions,
        proposer: draft.voting.approvals.first,
        createdAtUnix: Int64(Date().timeIntervalSince1970) - 18 * 60
    )
}

func makeDemoProposalInspection(
    squad: String,
    proposal: ProposalInspectionProposal,
    confidence: String? = nil
) -> ProposalInspectionReport {
    ProposalInspectionReport(
        kind: "proposal_inspection",
        squad: squad,
        cluster: "demo",
        action: makeDemoAction(for: proposal, confidenceOverride: confidence),
        simulation: ProposalInspectionSimulation(
            status: proposal.status == "approved" ? "succeeded" : "skipped",
            message: proposal.status == "approved"
                ? "Execution simulation completed successfully."
                : "Execution simulation can run once the proposal is ready.",
            error: nil,
            logs: ["Program log: demo simulation"],
            feePayer: proposal.voters.approve.first,
            recentBlockhash: "DemoRecentBlockhash1111111111111111111111111"
        ),
        proposal: proposal
    )
}

func makeDemoAction(
    for proposal: ProposalInspectionProposal,
    confidenceOverride: String? = nil
) -> RelayInspectionAction {
    let instruction = proposal.instructions.first
    let classification = instruction?.kind ?? "unknown"
    let summary = instruction?.summary ?? "Review raw instructions"
    let isUnknown = instruction?.program == "Unknown Program"
    let isTransfer = classification == "transfer"
    let effect = RelayInspectionEffect(
        kind: classification,
        summary: summary,
        program: instruction?.program,
        asset: demoAsset(from: summary, classification: classification),
        amount: demoAmount(from: summary),
        source: isTransfer ? proposal.accountsReferenced.first : nil,
        destination: isTransfer ? proposal.accountsReferenced.dropFirst().first : nil
    )
    return makeDemoAction(
        classification: classification,
        summary: summary,
        confidence: confidenceOverride ?? (isUnknown ? "unknown" : "decoded"),
        effect: effect,
        warnings: demoWarnings(for: proposal, isUnknown: isUnknown, isTransfer: isTransfer)
    )
}

func makeDemoAction(
    classification: String,
    summary: String,
    confidence: String,
    effect: RelayInspectionEffect,
    warnings: [RelayInspectionWarning] = []
) -> RelayInspectionAction {
    RelayInspectionAction(
        classification: classification,
        summary: summary,
        confidence: confidence,
        effects: [effect],
        warnings: warnings
    )
}

func makeDemoExecutedInspection(
    signature: String,
    slot: UInt64,
    blockTime: Int64,
    action: RelayInspectionAction,
    status: String = "finalized",
    error: String? = nil,
    logs: [String] = [
        "Program log: instruction decoded",
        "Program log: execution finalized"
    ]
) -> ExecutedTransactionInspectionReport {
    ExecutedTransactionInspectionReport(
        kind: "executed_transaction_inspection",
        signature: signature,
        cluster: "demo",
        status: ExecutedTransactionInspectionStatus(
            status: status,
            slot: slot,
            blockTime: blockTime,
            error: error
        ),
        action: action,
        logs: logs
    )
}

func makeDemoActivity(
    signature: String,
    slot: UInt64,
    kind: String,
    action: RelayInspectionAction?,
    error: String? = nil
) -> RelayActivityItem {
    RelayActivityItem(
        signature: signature,
        slot: slot,
        timestampUnix: 1_779_230_000 + Int64(slot % 10000),
        kind: kind,
        error: error,
        action: action
    )
}

func makeDemoToken(_ token: DemoTokenAsset) -> DASAsset {
    DASAsset(
        id: token.id,
        symbol: token.symbol,
        name: token.name,
        tokenAmount: token.amount,
        tokenDisplayAmount: token.display,
        decimals: token.decimals,
        tokenProgramID: token.token2022 ? HeliusDASClient.token2022ProgramID : HeliusDASClient.tokenProgramID,
        imageURI: nil,
        kind: .fungible
    )
}

func shortDemoAddress(_ value: String) -> String {
    guard value.count > 12 else {
        return value
    }
    return "\(value.prefix(4))...\(value.suffix(4))"
}

private func demoUnknownProgramWarning() -> RelayInspectionWarning {
    RelayInspectionWarning(
        severity: "high",
        code: "unknown_program",
        message: "Cosign could not identify a well-known action."
    )
}

private func demoWarnings(
    for proposal: ProposalInspectionProposal,
    isUnknown: Bool,
    isTransfer: Bool
) -> [RelayInspectionWarning] {
    if isUnknown {
        return [demoUnknownProgramWarning()]
    }

    guard
        isTransfer,
        proposal.status == "active",
        let destination = proposal.accountsReferenced.dropFirst().first
    else {
        return []
    }

    return [demoFirstTimeRecipientWarning(destination: destination)]
}

private func demoFirstTimeRecipientWarning(destination: String) -> RelayInspectionWarning {
    RelayInspectionWarning(
        severity: "warning",
        code: "first_time_recipient",
        message: "This vault has not sent to \(shortDemoAddress(destination)) before. Double-check with the proposer."
    )
}

private func demoAmount(from summary: String) -> String? {
    for prefix in ["Transfer ", "Sent "] where summary.hasPrefix(prefix) {
        return String(summary.dropFirst(prefix.count))
    }
    return nil
}

private func demoAsset(from summary: String, classification: String) -> String? {
    guard classification == "transfer" else {
        return nil
    }

    return demoAmount(from: summary)?
        .split(separator: " ")
        .last
        .map(String.init)
}
