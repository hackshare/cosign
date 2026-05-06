import Indexer
import Squads
import SwiftUI

extension ProposalDetailView {
    func proposalDecisionSection(_ proposal: SquadProposalDetail) -> some View {
        let action = proposalActionObject(for: proposal)

        return VStack(alignment: .leading, spacing: 14) {
            CosignSectionTitle(
                title: CosignCopy.ProposalDetail.proposalSectionTitle(index: proposal.transactionIndex),
                trailing: CosignCopy.ProposalDetail.proposalSectionTrailing(
                    kind: proposal.kind,
                    status: proposal.status
                )
            )
            ProposalDecisionHeader(
                action: action,
                proposal: proposal,
                squadAddress: squadAddress
            )
        }
    }

    @ViewBuilder
    func decodedFieldsSection(_ proposal: SquadProposalDetail) -> some View {
        let action = proposalActionObject(for: proposal)
        let decodedInstructions = instructionDecoder.decode(proposal)
        let roles = decodedFieldRoles(for: action, decodedInstructions: decodedInstructions)
        let instructionRows = decodedInstructionRows(roles: roles, decodedInstructions: decodedInstructions)
        let hasRoleAndInstructionRows = !roles.isEmpty && !instructionRows.isEmpty

        if !roles.isEmpty || !instructionRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalDetail.decodedFieldsSectionTitle)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        if !roles.isEmpty {
                            ForEach(Array(roles.enumerated()), id: \.element.id) { index, role in
                                RoleRow(
                                    role: role,
                                    isLast: index == roles.count - 1 && instructionRows.isEmpty
                                )
                            }
                        }

                        if hasRoleAndInstructionRows {
                            Divider()
                                .overlay(CosignTheme.line)
                        }

                        if !instructionRows.isEmpty {
                            decodedInstructionSummaryRows(instructionRows)
                        }
                    }
                }
            }
        }
    }

    private func decodedFieldRoles(
        for action: ActionObject,
        decodedInstructions: [DecodedInstructionDisplay]
    ) -> [ActionRole] {
        guard !decodedInstructions.isEmpty else {
            return action.roles
        }

        let structuralLabels = Set(["program", "instruction", "proposal"])
        return action.roles.filter { role in
            !structuralLabels.contains(role.label.lowercased())
        }
    }

    private func decodedInstructionRows(
        roles: [ActionRole],
        decodedInstructions: [DecodedInstructionDisplay]
    ) -> [DecodedInstructionDisplay] {
        if decodedInstructions.count > 1 || roles.isEmpty {
            return decodedInstructions
        }

        return []
    }

    @ViewBuilder
    func technicalDetailsSection(_ proposal: SquadProposalDetail) -> some View {
        let instructions = instructionDecoder.decode(proposal)
        let accounts = unique(proposal.accountsReferenced)
        let hasRelayInspection = inspectionReport != nil || executedInspectionReport != nil

        if !hasRelayInspection, !instructions.isEmpty || !accounts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalDetail.technicalDetailsSectionTitle)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        proposalFactsDisclosure(proposal)

                        if !instructions.isEmpty {
                            Divider()
                                .overlay(CosignTheme.line)
                                .padding(.leading, 14)
                            rawInstructionsDisclosure(instructions)
                        }

                        if !accounts.isEmpty {
                            Divider()
                                .overlay(CosignTheme.line)
                                .padding(.leading, 14)
                            rawAccountsDisclosure(accounts)
                        }
                    }
                }
            }
        }
    }

    func votesSection(_ proposal: SquadProposalDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ProposalDetail.votesSectionTitle)
            CosignCard(padding: 14) {
                if proposal.threshold > 0 {
                    HStack(spacing: 14) {
                        VoteProgressRing(approvals: proposal.votesYes, threshold: proposal.threshold)
                        voteProgressDetail(proposal)
                    }
                } else {
                    Text(CosignCopy.ProposalDetail.noApprovalThresholdMessage)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }
            }
        }
    }

    private func voteProgressDetail(_ proposal: SquadProposalDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                CosignCopy.ProposalDetail.approvalProgress(
                    approvals: proposal.votesYes,
                    threshold: proposal.threshold
                )
            )
            .font(CosignTheme.FontStyle.titleM)
            .foregroundStyle(CosignTheme.ink)
            .monospacedDigit()
            Text(voteStatusText(for: proposal))
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkDim)

            if let proposer = proposal.proposer {
                Text(CosignCopy.ProposalDetail.proposedBy(proposer, createdAtUnix: proposal.createdAtUnix))
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
            }

            HStack(spacing: 6) {
                VoteCountPill(
                    glyph: .check,
                    title: CosignCopy.ProposalDetail.approveVoteTitle,
                    value: proposal.votesYes
                )
                VoteCountPill(
                    glyph: .xmark,
                    title: CosignCopy.ProposalDetail.rejectVoteTitle,
                    value: proposal.votesNo
                )
                if proposal.votesCancelled > 0 {
                    VoteCountPill(
                        glyph: .xmark,
                        title: CosignCopy.ProposalDetail.cancelVoteTitle,
                        value: proposal.votesCancelled
                    )
                }
            }

            if !squadMembers.isEmpty {
                Divider()
                    .overlay(CosignTheme.line)
                    .padding(.top, 6)
                ProposalVoterChipCloud(members: squadMembers, proposal: proposal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func votersSection(title: String, addresses: [String]) -> some View {
        let visibleAddresses = unique(addresses)

        if !visibleAddresses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: title)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleAddresses.enumerated()), id: \.element) { index, address in
                            AddressRow(address: address)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            if index < visibleAddresses.count - 1 {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    private func decodedInstructionSummaryRows(_ instructions: [DecodedInstructionDisplay]) -> some View {
        ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
            DecodedInstructionSummaryRow(index: index + 1, instruction: instruction)
            if index < instructions.count - 1 {
                Divider()
                    .overlay(CosignTheme.line)
                    .padding(.leading, 14)
            }
        }
    }

    func proposalActionObject(for proposal: SquadProposalDetail) -> ActionObject {
        let localAction = localDecodedAction(for: proposal)

        if let action = executedInspectionReport?.action {
            let actionObject = action.actionObject(context: .executed)
            return actionObject.usesGenericReviewCopy ? localAction ?? actionObject : actionObject
        }
        if let action = inspectionReport?.action {
            let actionObject = action.actionObject
            return actionObject.usesGenericReviewCopy ? localAction ?? actionObject : actionObject
        }

        if let localAction {
            return localAction
        }

        return ActionObject(
            title: CosignCopy.ProposalDetail.proposalReviewTitle(index: proposal.transactionIndex),
            subtitle: CosignCopy.ProposalDetail.proposalReviewSubtitle(kind: proposal.kind),
            severity: .routine,
            confidence: .unknown,
            source: CosignCopy.ProposalDetail.squadsSource,
            roles: [
                ActionRole(
                    label: CosignCopy.ProposalDetail.proposalRoleLabel,
                    value: CosignCopy.ProposalDetail.proposalNumber(index: proposal.transactionIndex)
                ),
                ActionRole(label: CosignCopy.ProposalDetail.squadLabel, value: squadAddress, isAddressLike: true)
            ],
            warnings: []
        )
    }

    private func localDecodedAction(for proposal: SquadProposalDetail) -> ActionObject? {
        guard let instruction = instructionDecoder.decode(proposal).first else {
            return nil
        }

        if instruction.kind.lowercased() != "raw" {
            return ActionObject(
                title: instruction.summary,
                subtitle: CosignCopy.ProposalDetail.decodedActionSubtitle(
                    programLabel: instruction.programLabel,
                    kind: instruction.kind
                ),
                severity: .routine,
                confidence: .partial,
                source: instruction.programLabel,
                roles: [
                    ActionRole(label: CosignCopy.ProposalDetail.programRoleLabel, value: instruction.programLabel),
                    ActionRole(
                        label: CosignCopy.ProposalDetail.instructionRoleLabel,
                        value: displayLabel(instruction.kind)
                    ),
                    ActionRole(
                        label: CosignCopy.ProposalDetail.proposalRoleLabel,
                        value: CosignCopy.ProposalDetail.proposalNumber(index: proposal.transactionIndex)
                    )
                ],
                warnings: []
            )
        }

        return nil
    }

    private func voteStatusText(for proposal: SquadProposalDetail) -> String {
        switch proposal.status.lowercased() {
        case "approved":
            return CosignCopy.ProposalDetail.readyToExecuteStatus
        case "executed":
            return CosignCopy.ProposalDetail.executedAfterThresholdStatus
        case "active":
            let remaining = max(Int(proposal.threshold) - Int(proposal.votesYes), 0)
            return remaining == 0
                ? CosignCopy.ProposalDetail.thresholdReachedStatus
                : CosignCopy.ProposalDetail.remainingApprovalStatus(remaining: remaining)
        default:
            return displayLabel(proposal.status)
        }
    }

    private func proposalFactsDisclosure(_ proposal: SquadProposalDetail) -> some View {
        CosignDisclosure(
            title: CosignCopy.ProposalDetail.proposalFactsTitle,
            subtitle: CosignCopy.ProposalDetail.proposalFactsSubtitle(
                kind: proposal.kind,
                index: proposal.transactionIndex
            )
        ) {
            VStack(spacing: 0) {
                CosignKeyValueRow(label: CosignCopy.ProposalDetail.typeLabel, value: displayLabel(proposal.kind))
                CosignKeyValueRow(
                    label: CosignCopy.ProposalDetail.transactionLabel,
                    value: String(proposal.transactionIndex)
                )
                CosignKeyValueRow(label: CosignCopy.ProposalDetail.thresholdLabel, value: String(proposal.threshold))
                CosignKeyValueRow(
                    label: CosignCopy.ProposalDetail.squadLabel,
                    value: squadAddress,
                    isAddressLike: true,
                    isLast: true
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func rawInstructionsDisclosure(_ instructions: [DecodedInstructionDisplay]) -> some View {
        CosignDisclosure(
            title: CosignCopy.ProposalDetail.rawInstructionsTitle,
            subtitle: CosignCopy.ProposalDetail.rawInstructionsSubtitle(count: instructions.count)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                    if index > 0 {
                        Divider()
                            .overlay(CosignTheme.line)
                    }
                    InstructionRow(index: index + 1, instruction: instruction)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func rawAccountsDisclosure(_ accounts: [String]) -> some View {
        CosignDisclosure(
            title: CosignCopy.ProposalDetail.rawAccountsTitle,
            subtitle: CosignCopy.ProposalDetail.rawAccountsSubtitle(count: accounts.count)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(accounts, id: \.self) { account in
                    AddressRow(address: account)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
