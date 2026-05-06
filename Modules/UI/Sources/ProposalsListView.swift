import Indexer
import Squads
import SwiftUI

public struct ProposalsListView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.indexerEnvironment) private var indexerEnvironment
    @Environment(\.squadsService) private var squadsService

    private let squadAddress: String
    private let latestTransactionIndex: UInt64
    private let pageSize: UInt64

    @State private var proposals = [SquadProposalSummary]()
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(squadAddress: String, latestTransactionIndex: UInt64, pageSize: UInt64 = 50) {
        self.squadAddress = squadAddress
        self.latestTransactionIndex = latestTransactionIndex
        self.pageSize = pageSize
    }

    public var body: some View {
        CosignScreen {
            CosignCompactPageHeader { coordinator.pop() }
            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.ProposalList.historySection)
                Text(CosignCopy.ProposalList.screenTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }
            summarySection
            proposalsContent
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await load(forceRefresh: true)
        }
        .task(id: taskID) {
            await load()
        }
        .pollingRefresh(
            id: "proposals-\(taskID)",
            interval: ReadPollingInterval.proposal,
            enabled: proposalRange != nil
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
        .webSocketRefresh(
            id: "proposals-\(taskID)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: [squadAddress],
            enabled: proposalRange != nil
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
    }

    private var summarySection: some View {
        CosignCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(CosignCopy.ProposalList.squadLabel)
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Text(squadAddress)
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                CosignKeyValueRow(label: CosignCopy.ProposalList.latestIndexLabel, value: "\(latestTransactionIndex)")
                if let proposalRange {
                    CosignKeyValueRow(
                        label: CosignCopy.ProposalList.loadedRangeLabel,
                        value: CosignCopy.ProposalList.loadedRange(
                            from: proposalRange.fromIndex,
                            to: proposalRange.toIndex
                        ),
                        isLast: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var proposalsContent: some View {
        if proposalRange == nil {
            CosignEmptyState(key: .emptyProposals)
        } else if isLoading, proposals.isEmpty {
            CosignLoadingCard()
        } else if let errorMessage {
            CosignEmptyState(
                title: CosignCopy.ProposalList.unableToLoadTitle,
                systemImage: "exclamationmark.triangle",
                message: errorMessage
            )
            Button {
                Task {
                    await load()
                }
            } label: {
                Text(CosignCopy.Activity.retryButton)
                    .cosignSecondaryAction()
            }
            .buttonStyle(.plain)
        } else if proposals.isEmpty {
            CosignEmptyState(key: .emptyProposals)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalList.screenTitle)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(proposals.enumerated()), id: \.element.id) { index, proposal in
                            CosignObjectRowButton {
                                coordinator.go(to: .proposalDetail(
                                    squad: squadAddress,
                                    txIndex: proposal.transactionIndex
                                ))
                            } label: {
                                ProposalSummaryRow(proposal: proposal)
                            }
                            .accessibilityIdentifier("proposal-row-\(index)")

                            if index < proposals.count - 1 {
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

    private var proposalRange: ProposalRange? {
        ProposalRange.recent(through: latestTransactionIndex, limit: pageSize)
    }

    private var taskID: String {
        "\(squadAddress)-\(latestTransactionIndex)-\(pageSize)"
    }

    @MainActor
    private func load(forceRefresh: Bool = false, showsLoading: Bool = true) async {
        guard let proposalRange else {
            proposals = []
            errorMessage = nil
            return
        }

        if showsLoading {
            isLoading = true
        }
        if proposals.isEmpty || showsLoading {
            errorMessage = nil
        }
        defer {
            if showsLoading {
                isLoading = false
            }
        }

        do {
            proposals = if forceRefresh {
                try await squadsService.refreshProposals(in: squadAddress, range: proposalRange)
            } else {
                try await squadsService.proposals(in: squadAddress, range: proposalRange)
            }
            errorMessage = nil
        } catch {
            if proposals.isEmpty {
                errorMessage = String(describing: error)
            }
        }
    }
}

struct ProposalsPreviewSection: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.indexerEnvironment) private var indexerEnvironment
    @Environment(\.squadsService) private var squadsService

    let squadAddress: String
    let latestTransactionIndex: UInt64
    let onRecentActivity: (() -> Void)?

    @State private var proposals = [SquadProposalSummary]()
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(
        squadAddress: String,
        latestTransactionIndex: UInt64,
        onRecentActivity: (() -> Void)? = nil
    ) {
        self.squadAddress = squadAddress
        self.latestTransactionIndex = latestTransactionIndex
        self.onRecentActivity = onRecentActivity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if proposalRange == nil {
                CosignEmptyState(key: .emptyProposals, primaryAction: onRecentActivity)
            } else if isLoading, proposals.isEmpty {
                CosignLoadingCard()
            } else if let errorMessage {
                CosignEmptyState(
                    title: CosignCopy.ProposalList.unableToLoadTitle,
                    systemImage: "exclamationmark.triangle",
                    message: errorMessage
                )
                Button {
                    Task {
                        await load()
                    }
                } label: {
                    Text(CosignCopy.Activity.retryButton)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if proposals.isEmpty {
                CosignEmptyState(key: .emptyProposals, primaryAction: onRecentActivity)
            } else {
                CosignSectionTitle(title: CosignCopy.ProposalList.recentProposalsSection)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(proposals.enumerated()), id: \.element.id) { index, proposal in
                            CosignObjectRowButton {
                                coordinator.go(to: .proposalDetail(
                                    squad: squadAddress,
                                    txIndex: proposal.transactionIndex
                                ))
                            } label: {
                                ProposalSummaryRow(proposal: proposal)
                            }
                            .accessibilityIdentifier("proposal-preview-row-\(index)")

                            if index < proposals.count - 1 {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                        }

                        Divider()
                            .overlay(CosignTheme.line)
                            .padding(.leading, 14)

                        CosignObjectRowButton {
                            coordinator.go(to: .proposals(
                                squad: squadAddress,
                                latestIndex: latestTransactionIndex
                            ))
                        } label: {
                            CosignObjectRow(
                                title: CosignCopy.ProposalList.allProposalsTitle,
                                style: .plain,
                                leading: {
                                    CosignGlyphView(glyph: .list, size: 18, color: CosignTheme.accentDeep)
                                        .frame(width: 36, height: 36)
                                }
                            )
                        }
                    }
                }
            }
        }
        .task(id: taskID) {
            await load()
        }
        .pollingRefresh(
            id: "proposals-preview-\(taskID)",
            interval: ReadPollingInterval.proposal,
            enabled: proposalRange != nil
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
        .webSocketRefresh(
            id: "proposals-preview-\(taskID)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: [squadAddress],
            enabled: proposalRange != nil
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
    }

    private var proposalRange: ProposalRange? {
        ProposalRange.recent(through: latestTransactionIndex, limit: 5)
    }

    private var taskID: String {
        "\(squadAddress)-\(latestTransactionIndex)"
    }

    @MainActor
    private func load(forceRefresh: Bool = false, showsLoading: Bool = true) async {
        guard let proposalRange else {
            proposals = []
            errorMessage = nil
            return
        }

        if showsLoading {
            isLoading = true
        }
        if proposals.isEmpty || showsLoading {
            errorMessage = nil
        }
        defer {
            if showsLoading {
                isLoading = false
            }
        }

        do {
            proposals = if forceRefresh {
                try await squadsService.refreshProposals(in: squadAddress, range: proposalRange)
            } else {
                try await squadsService.proposals(in: squadAddress, range: proposalRange)
            }
            errorMessage = nil
        } catch {
            if proposals.isEmpty {
                errorMessage = String(describing: error)
            }
        }
    }
}
