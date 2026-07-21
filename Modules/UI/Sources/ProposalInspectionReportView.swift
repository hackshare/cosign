import Indexer
import Squads
import SwiftUI

struct ProposalInspectionReportView: View {
    let report: ProposalInspectionReport
    let instructionDecoder: InstructionDecoder
    var idls: [String: ResolvedProgramIDL] = [:]
    var specs: [String: [DecodeSpec]] = [:]
    var resolvedMints: [String: ResolvedMint] = [:]
    let showsSimulation: Bool
    var showsAction = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsAction {
                RelayInspectionActionView(
                    action: report.action,
                    fallbackLabel: actionBadgeLabel,
                    fallbackColor: actionBadgeColor
                )
            }
            instructionDetails
            if showsSimulation, report.simulation.isVisible {
                simulationSummary
            }
        }
        .padding(.vertical, 4)
    }

    private var decodedInstructions: [DecodedInstructionDisplay] {
        let mints = resolvedMints.mapValues { MintInfo(
            symbol: $0.symbol ?? cosignShortAddress($0.mint),
            decimals: $0.decimals
        ) }
        // This view has no vault-account set, so it cannot compute a meaningful verdict; the
        // authoritative cross-check runs in ProposalDetailView. Pass nil rather than an inert context.
        return report.proposal.instructions.map { instruction in
            instructionDecoder.decode(
                instruction.squadInstruction, idls: idls, specs: specs, mints: mints, crossCheck: nil
            )
        }
    }

    private var actionBadgeLabel: String {
        if let action = report.action, action.classification != "unknown" {
            return displayLabel(action.classification)
        }

        switch decodedInstructions.count {
        case 0:
            return CosignCopy.ProposalDetail.instructionFallbackTitle(count: 0)
        case 1:
            return displayLabel(decodedInstructions[0].kind)
        default:
            return CosignCopy.ProposalDetail.instructionFallbackTitle(count: decodedInstructions.count)
        }
    }

    private var actionBadgeColor: Color {
        if let action = report.action {
            return action.confidence.lowercased() == "low" ? CosignTheme.inkDim : CosignTheme.accentDeep
        }

        return decodedInstructions.contains { $0.kind.lowercased() != "raw" }
            ? CosignTheme.accentDeep
            : CosignTheme.inkDim
    }

    @ViewBuilder
    private var simulationSummary: some View {
        Divider()
            .overlay(CosignTheme.line)

        CosignDisclosure(
            title: CosignCopy.ProposalDetail.simulationTitle,
            subtitle: displayLabel(report.simulation.status)
        ) {
            Text(report.simulation.message)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.inkDim)

            if let error = report.simulation.error {
                Text(error)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.riskRed)
                    .textSelection(.enabled)
            }

            simulationMetadata
            simulationLogs
        }
    }

    @ViewBuilder
    private var simulationMetadata: some View {
        if report.simulation.feePayer != nil || report.simulation.recentBlockhash != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let feePayer = report.simulation.feePayer {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CosignCopy.ProposalDetail.feePayerTitle)
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkFaint)
                        AddressRow(address: feePayer)
                    }
                }

                if let recentBlockhash = report.simulation.recentBlockhash {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CosignCopy.ProposalDetail.recentBlockhashTitle)
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkFaint)
                        AddressRow(address: recentBlockhash)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var simulationLogs: some View {
        if !report.simulation.logs.isEmpty {
            CosignDisclosure(title: CosignCopy.ProposalDetail.simulationLogsTitle) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(report.simulation.logs.enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(CosignTheme.FontStyle.monoSmall)
                            .foregroundStyle(CosignTheme.inkFaint)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var instructionDetails: some View {
        if decodedInstructions.isEmpty {
            Text(CosignCopy.ProposalDetail.noInstructionsMessage)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.inkDim)
        } else {
            CosignDisclosure(
                title: CosignCopy.ProposalDetail.instructionDetailsTitle,
                subtitle: CosignCopy.ProposalDetail.instructionCount(decodedInstructions.count),
                startsExpanded: false
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(decodedInstructions.enumerated()), id: \.offset) { index, instruction in
                        if index > 0 {
                            Divider()
                                .overlay(CosignTheme.line)
                        }
                        InstructionRow(index: index + 1, instruction: instruction)
                    }
                }
            }
        }
    }
}

private extension ProposalInspectionInstruction {
    var squadInstruction: SquadDecodedInstruction {
        SquadDecodedInstruction(
            program: program,
            kind: kind,
            summary: summary,
            accounts: accounts,
            rawDataHex: rawDataHex
        )
    }
}

private extension ProposalInspectionSimulation {
    var isVisible: Bool {
        switch status.lowercased() {
        case "succeeded", "failed":
            true
        default:
            false
        }
    }
}
