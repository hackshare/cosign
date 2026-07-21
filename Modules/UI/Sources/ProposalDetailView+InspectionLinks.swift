import Indexer
import Squads
import SwiftUI

struct ProposalLink {
    let url: URL
    let label: String
    let systemImage: String
}

extension ProposalDetailView {
    @ViewBuilder
    func inspectionSection(_ proposal: SquadProposalDetail) -> some View {
        let manualSimulationLink = manualSimulationLink(for: proposal)
        let canLoadRelayInspection = canLoadRelayInspection(for: proposal)
        let shouldShowInspection = canLoadRelayInspection
            || manualSimulationLink != nil
            || inspectionReport != nil
            || executedInspectionReport != nil
            || isLoadingInspection
            || inspectionErrorMessage != nil

        if shouldShowInspection {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.TransactionInspection.inspectionSectionTitle)
                CosignCard {
                    VStack(alignment: .leading, spacing: 12) {
                        inspectionActionButton(for: proposal, manualSimulationLink: manualSimulationLink)
                        inspectionCardContent(for: proposal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inspectionCardContent(for proposal: SquadProposalDetail) -> some View {
        if let executedInspectionReport {
            ExecutedTransactionInspectionReportView(
                report: executedInspectionReport,
                showsAction: false
            )
        } else if let inspectionReport {
            ProposalInspectionReportView(
                report: inspectionReport,
                instructionDecoder: instructionDecoder,
                idls: resolvedIDLs,
                specs: resolvedSpecs,
                resolvedMints: resolvedMints,
                showsSimulation: !proposal.isExecuted,
                showsAction: false
            )
        } else if isLoadingInspection {
            ProposalInspectionSkeletonView()
        } else if let inspectionErrorMessage {
            CosignInlineBanner(tone: .red) {
                Text(inspectionErrorMessage)
            }
        }
    }

    @ViewBuilder
    private func inspectionActionButton(
        for proposal: SquadProposalDetail,
        manualSimulationLink: ProposalLink?
    ) -> some View {
        if canLoadRelayInspection(for: proposal) {
            Button {
                Task {
                    await loadInspectionForCurrentProposal()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                    Text(inspectionRefreshLabel(for: proposal))
                }
            }
            .buttonStyle(CosignButtonStyle(kind: .secondary))
            .disabled(isLoadingInspection)
        } else if let manualSimulationLink {
            Link(destination: manualSimulationLink.url) {
                CosignNavigationRow(
                    title: manualSimulationLink.label,
                    systemImage: manualSimulationLink.systemImage
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    func linksSection(_ proposal: SquadProposalDetail) -> some View {
        let executionLink = executionExplorerLink(for: proposal)

        if executionLink != nil {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalDetail.linksSectionTitle)
                CosignCard {
                    if let executionLink {
                        Link(destination: executionLink.url) {
                            CosignNavigationRow(
                                title: executionLink.label,
                                systemImage: "arrow.up.forward.square"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    func manualSimulationLink(for proposal: SquadProposalDetail) -> ProposalLink? {
        guard proposal.canOpenManualSimulation else {
            return nil
        }

        guard
            proposal.kind.lowercased() == "vault",
            let transactionAddress = proposal.transactionAddress,
            let explorerURL = SolanaExplorer.squadsTransactionInspectorURL(
                transactionAddress: transactionAddress,
                rpcURL: indexerEnvironment.effectiveExplorerRPCURL
            )
        else {
            return nil
        }

        return ProposalLink(
            url: explorerURL,
            label: CosignCopy.ProposalDetail.simulateTransactionTitle,
            systemImage: "play.circle"
        )
    }

    func executionExplorerLink(for proposal: SquadProposalDetail) -> SolanaExplorerExecutionLink? {
        guard proposal.isExecuted else {
            return nil
        }

        return SolanaExplorer.executedProposalLink(
            executionSignature: executionSignature,
            transactionAddress: proposal.transactionAddress,
            rpcURL: indexerEnvironment.effectiveExplorerRPCURL
        )
    }

    func canLoadRelayInspection(for proposal: SquadProposalDetail) -> Bool {
        let request = ProposalInspectionRequest(
            squadAddress: squadAddress,
            transactionIndex: proposal.transactionIndex
        )
        return indexerEnvironment.relay.proposalInspectionURL(for: request) != nil
    }

    func inspectionRefreshLabel(for proposal: SquadProposalDetail) -> String {
        if isLoadingInspection {
            return CosignCopy.ProposalDetail.refreshingInspectionTitle
        }
        return proposal.canRefreshRelaySimulation
            ? CosignCopy.ProposalDetail.refreshInspectionAndSimulationTitle
            : CosignCopy.ProposalDetail.refreshInspectionTitle
    }

    @MainActor
    func resolveDecodeSpecs() async {
        resolvedSpecs = await DecodeRegistryResolver(relay: indexerEnvironment.relay).resolve()
    }

    @MainActor
    func resolveIDLs() async {
        guard let proposal else { return }
        let programs = instructionDecoder.programsNeedingIDL(in: proposal)
        guard !programs.isEmpty else {
            resolvedIDLs = [:]
            return
        }
        let resolver = ProgramIDLResolver(relay: indexerEnvironment.relay)
        resolvedIDLs = await resolver.resolve(programIDs: programs)
    }

    @MainActor
    func resolveMints() async {
        guard let proposal else { return }
        let accounts = unique(proposal.accountsReferenced + proposal.instructions.flatMap(\.accounts))
        resolvedMints = await MintResolver(relay: indexerEnvironment.relay).resolve(accounts: accounts)
    }
}

private extension SolanaExplorerExecutionLink {
    var label: String {
        switch kind {
        case .executedTransaction:
            CosignCopy.ProposalDetail.openExecutedTransactionTitle
        case .transactionAccount:
            CosignCopy.ProposalDetail.openTransactionAccountTitle
        }
    }
}

private struct ProposalInspectionSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                CosignSkeletonBar(width: 72, height: 20, cornerRadius: 10)
                CosignSkeletonBar(width: 96, height: 20, cornerRadius: 10)
            }
            CosignSkeletonBar(width: nil, height: 20)
            CosignSkeletonBar(width: 190, height: 14)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0 ..< 4, id: \.self) { index in
                    HStack(spacing: 14) {
                        CosignSkeletonBar(width: 52, height: 10)
                        CosignSkeletonBar(width: index.isMultiple(of: 2) ? 170 : 120, height: 12)
                    }
                }
            }
            .padding(14)
            .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                    .stroke(CosignTheme.line, lineWidth: 1)
            }
        }
        .padding(.vertical, 4)
    }
}
