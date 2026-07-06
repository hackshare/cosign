import Indexer
import Squads
import SwiftUI

public struct TransactionInspectionView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.indexerEnvironment) private var indexerEnvironment
    @Environment(\.squadsService) private var squadsService

    private let signature: String
    private let squadAddress: String?

    @State private var report: ExecutedTransactionInspectionReport?
    @State private var ownVaultAccounts: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(signature: String, squad: String? = nil) {
        self.signature = signature
        squadAddress = squad
    }

    public var body: some View {
        CosignScreen {
            CosignCompactPageHeader(title: CosignCopy.TransactionInspection.navigationTitle) {
                coordinator.pop()
            }

            transactionHero
            movementSection
            transactionSection
            inspectionSection
        }
        .accessibilityIdentifier("screen.transaction-inspection")
        .navigationBarBackButtonHidden(true)
        .refreshable {
            await load(forceRefresh: true)
        }
        .task(id: taskID) {
            await load()
        }
        .task(id: squadAddress) {
            await loadOwnVaultAccounts()
        }
        .pollingRefresh(
            id: "transaction-inspection-\(taskID)",
            interval: ReadPollingInterval.activity,
            enabled: canLoadInspection
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
    }

    private var taskID: String {
        "\(signature)-\(indexerEnvironment.effectiveRPCURL.absoluteString)"
    }

    private var canLoadInspection: Bool {
        let request = ExecutedTransactionInspectionRequest(signature: signature)
        return indexerEnvironment.relay.executedTransactionInspectionURL(for: request) != nil
    }

    private var transactionHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: report == nil
                ? CosignCopy.TransactionInspection.relayInspectionTitle
                : CosignCopy.TransactionInspection.executedTransactionTitle)

            if let report {
                ActionHeaderView(
                    action: report.action.actionObject(context: .executed),
                    size: .large
                )
            } else {
                Text(CosignCopy.TransactionInspection.transactionTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }
        }
    }

    /// Classifies the transaction's effects against the squad's own vault
    /// addresses to render the asset-movement card. When reached without squad
    /// context (a cross-squad feed), ownVaultAccounts stays empty and the card
    /// is hidden.
    @ViewBuilder
    private var movementSection: some View {
        if let report {
            let movement = AssetMovement.build(from: report.action.effects, ownAccounts: ownVaultAccounts)
            if !movement.isEmpty {
                AssetMovementCard(movement: movement, variant: report.status.error != nil ? .attempted : .executed)
            }
        }
    }

    private var transactionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.TransactionInspection.transactionTitle)
            CosignCard {
                CosignAddressBlock(
                    title: CosignCopy.TransactionInspection.signatureTitle,
                    address: signature,
                    accessibilityLabel: CosignCopy.TransactionInspection.copySignatureAccessibilityLabel
                )

                if let explorerURL {
                    Link(destination: explorerURL) {
                        CosignNavigationRow(
                            title: CosignCopy.TransactionInspection.openInExplorerTitle,
                            systemImage: "arrow.up.forward.square"
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }
        }
    }

    private var inspectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.TransactionInspection.inspectionSectionTitle)
            if let report {
                CosignCard {
                    ExecutedTransactionInspectionReportView(report: report, showsAction: false)
                }
            } else if isLoading {
                CosignLoadingCard()
            } else if let errorMessage {
                CosignEmptyState(
                    title: CosignCopy.TransactionInspection.unableToInspectTitle,
                    systemImage: "exclamationmark.triangle",
                    message: errorMessage
                )
                Button {
                    Task {
                        await load(forceRefresh: true)
                    }
                } label: {
                    Text(CosignCopy.TransactionInspection.retryButton)
                        .cosignSecondaryAction()
                }
                .buttonStyle(.plain)
            } else {
                CosignEmptyState(key: .noRelayInspection)
            }
        }
    }

    private var explorerURL: URL? {
        SolanaExplorer.transactionURL(signature: signature, rpcURL: indexerEnvironment.effectiveExplorerRPCURL)
    }

    @MainActor
    private func load(forceRefresh: Bool = false, showsLoading: Bool = true) async {
        guard canLoadInspection else {
            if report == nil || forceRefresh {
                errorMessage = nil
            }
            return
        }

        if showsLoading {
            isLoading = true
        }
        if report == nil || forceRefresh {
            errorMessage = nil
        }
        defer {
            if showsLoading {
                isLoading = false
            }
        }

        do {
            let request = ExecutedTransactionInspectionRequest(signature: signature)
            report = try await indexerEnvironment.relay.executedTransactionInspectionReport(for: request)
            errorMessage = nil
        } catch {
            if report == nil || forceRefresh {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadOwnVaultAccounts() async {
        guard let squadAddress else {
            ownVaultAccounts = []
            return
        }
        ownVaultAccounts = await (try? squadsService.ownVaultAddresses(of: squadAddress)) ?? []
    }
}

struct ExecutedTransactionInspectionReportView: View {
    let report: ExecutedTransactionInspectionReport
    var showsAction = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsAction {
                RelayInspectionActionView(
                    action: report.action,
                    fallbackLabel: displayLabel(report.action.classification),
                    fallbackColor: actionBadgeColor,
                    context: .executed
                )
            }
            executionStatus
            executionLogs
        }
        .padding(.vertical, 4)
    }

    private var actionBadgeColor: Color {
        report.action.confidence.lowercased() == "low" ? CosignTheme.inkDim : CosignTheme.accentDeep
    }

    private var executionStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsAction {
                Divider()
                    .overlay(CosignTheme.line)
            }

            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    CosignGlyphView(
                        glyph: report.status.error == nil ? .check : .xmark,
                        size: 16,
                        color: report.status.error == nil ? CosignTheme.mintDeep : CosignTheme.riskRed
                    )
                    Text(CosignCopy.TransactionInspection.executionTitle)
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.ink)
                }
                Spacer()
                InspectionBadge(
                    label: displayLabel(report.status.status),
                    color: report.status.error == nil ? CosignTheme.mint : CosignTheme.riskRed
                )
            }

            if let slot = report.status.slot {
                CosignKeyValueRow(
                    label: CosignCopy.TransactionInspection.slotLabel,
                    value: String(slot),
                    isLast: report.status.error == nil
                )
            }

            if let error = report.status.error {
                Text(error)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.riskRed)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var executionLogs: some View {
        if !report.logs.isEmpty {
            CosignDisclosure(
                title: CosignCopy.TransactionInspection.executionLogsTitle,
                subtitle: CosignCopy.TransactionInspection.logCount(report.logs.count)
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(report.logs.enumerated()), id: \.offset) { _, log in
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
}
