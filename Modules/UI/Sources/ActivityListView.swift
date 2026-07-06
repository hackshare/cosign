import Indexer
import Squads
import SwiftUI

public struct ActivityListView: View {
    @Environment(\.indexerEnvironment) private var indexerEnvironment
    @Environment(\.squadsService) private var squadsService
    @Environment(Coordinator.self) private var coordinator

    private let squadAddress: String
    private let pageSize: UInt32

    @State private var items = [SquadActivityItem]()
    @State private var ownVaultAccounts = Set<String>()
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedFilter: ActivityFilter = .all

    public init(squadAddress: String, pageSize: UInt32 = 50) {
        self.squadAddress = squadAddress
        self.pageSize = pageSize
    }

    public var body: some View {
        CosignScreen {
            CosignCompactPageHeader { coordinator.pop() }
            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.Activity.historySection)
                Text(CosignCopy.Activity.screenTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }
            CosignSearchField(placeholder: CosignCopy.Activity.searchPlaceholder, text: $searchText)
            activityFilters
            summarySection
            activityContent
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await reload(forceRefresh: true)
        }
        .task(id: squadAddress) {
            await reload()
        }
        .pollingRefresh(
            id: "activity-\(squadAddress)-\(pageSize)",
            interval: ReadPollingInterval.activity,
            enabled: !squadAddress.isEmpty
        ) {
            await reload(forceRefresh: true, showsLoading: false)
        }
        .webSocketRefresh(
            id: "activity-\(squadAddress)-\(pageSize)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: [squadAddress],
            enabled: !squadAddress.isEmpty
        ) {
            await reload(forceRefresh: true, showsLoading: false)
        }
        .accessibilityIdentifier("screen.activity")
    }

    private var summarySection: some View {
        CosignCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(CosignCopy.Activity.squadLabel)
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Text(squadAddress)
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private var activityContent: some View {
        if isLoading, items.isEmpty {
            CosignLoadingCard()
        } else if let errorMessage, items.isEmpty {
            CosignEmptyState(
                title: CosignCopy.Activity.unableToLoadTitle,
                systemImage: "exclamationmark.triangle",
                message: errorMessage
            )
            Button {
                Task {
                    await reload()
                }
            } label: {
                Text(CosignCopy.Activity.retryButton)
                    .cosignSecondaryAction()
            }
            .buttonStyle(.plain)
        } else if displayedItems.isEmpty {
            if items.isEmpty {
                CosignEmptyState(key: .emptyActivity)
            } else {
                CosignEmptyState(
                    title: CosignCopy.Activity.noMatchesTitle,
                    systemImage: "clock.arrow.circlepath",
                    message: CosignCopy.Activity.noMatchesMessage
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.Activity.transactionsSection)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                            ActivityNavigationRow(
                                item: item,
                                explorerURL: SolanaExplorer.transactionURL(
                                    signature: item.signature,
                                    rpcURL: indexerEnvironment.effectiveExplorerRPCURL
                                ),
                                canInspect: canInspectTransaction(item),
                                ownVaultAccounts: ownVaultAccounts,
                                squadAddress: squadAddress
                            )
                            .accessibilityIdentifier("activity-row-\(index)")

                            if index < displayedItems.count - 1 || canLoadMore {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                        }

                        if canLoadMore {
                            Button {
                                Task {
                                    await loadMore()
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoadingMore {
                                        ProgressView()
                                            .tint(CosignTheme.accentDeep)
                                    } else {
                                        Text(CosignCopy.Activity.loadMoreButton)
                                            .font(CosignTheme.FontStyle.body)
                                            .foregroundStyle(CosignTheme.ink)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingMore)
                        }
                    }
                }
            }

            if let errorMessage {
                CosignCard {
                    HStack(alignment: .top, spacing: 8) {
                        CosignGlyphView(glyph: .warning, size: 16, color: CosignTheme.riskAmber)
                        Text(errorMessage)
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkDim)
                    }
                }
            }
        }
    }

    private var activityFilters: some View {
        HStack(spacing: 8) {
            ForEach(ActivityFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.title)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(selectedFilter == filter ? CosignTheme.accentInk : CosignTheme.inkDim)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .background(
                            selectedFilter == filter ? CosignTheme.accent : CosignTheme.surface,
                            in: .capsule
                        )
                        .overlay {
                            Capsule().stroke(CosignTheme.line, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var displayedItems: [SquadActivityItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            selectedFilter.includes(item) && (
                query.isEmpty ||
                    item.signature.lowercased().contains(query) ||
                    item.kind.lowercased().contains(query) ||
                    item.action?.summary.lowercased().contains(query) == true ||
                    item.action?.classification.lowercased().contains(query) == true
            )
        }
    }

    @MainActor
    private func reload(forceRefresh: Bool = false, showsLoading: Bool = true) async {
        if showsLoading {
            isLoading = true
        }
        if items.isEmpty || showsLoading {
            errorMessage = nil
        }
        defer {
            if showsLoading {
                isLoading = false
            }
        }

        do {
            async let newVaultAccounts = vaultAccountAddresses()
            let page = if forceRefresh {
                try await squadsService.refreshActivity(in: squadAddress, before: nil, limit: pageSize)
            } else {
                try await squadsService.activity(in: squadAddress, before: nil, limit: pageSize)
            }
            ownVaultAccounts = await newVaultAccounts
            items = page
            canLoadMore = page.count == Int(pageSize)
            errorMessage = nil
        } catch {
            if items.isEmpty {
                canLoadMore = false
                errorMessage = String(describing: error)
            }
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoadingMore, let before = items.last?.signature else {
            return
        }

        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let page = try await squadsService.activity(in: squadAddress, before: before, limit: pageSize)
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: page.filter { !existingIDs.contains($0.id) })
            canLoadMore = page.count == Int(pageSize)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func vaultAccountAddresses() async -> Set<String> {
        await (try? squadsService.ownVaultAddresses(of: squadAddress)) ?? []
    }

    private func canInspectTransaction(_ item: SquadActivityItem) -> Bool {
        let request = ExecutedTransactionInspectionRequest(signature: item.signature)
        return indexerEnvironment.relay.executedTransactionInspectionURL(for: request) != nil
    }
}
