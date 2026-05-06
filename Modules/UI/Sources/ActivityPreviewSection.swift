import Indexer
import Squads
import SwiftUI

struct ActivityPreviewSection: View {
    @Environment(\.indexerEnvironment) private var indexerEnvironment
    @Environment(\.squadsService) private var squadsService

    let squadAddress: String

    @State private var items = [SquadActivityItem]()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: ActivityFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoading, items.isEmpty {
                CosignLoadingCard()
            } else if let errorMessage {
                CosignEmptyState(
                    title: CosignCopy.Activity.unableToLoadTitle,
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
            } else if items.isEmpty {
                emptyActivityPreview
            } else {
                CosignSectionTitle(title: CosignCopy.Activity.recentActivitySection)
                CosignSegmentedControl(
                    labels: ActivityFilter.allCases.map(\.title),
                    selectedIndex: filterIndexBinding
                )
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(displayedItems.enumerated()), id: \.element.id) { _, item in
                            ActivityNavigationRow(
                                item: item,
                                explorerURL: SolanaExplorer.transactionURL(
                                    signature: item.signature,
                                    rpcURL: indexerEnvironment.effectiveExplorerRPCURL
                                ),
                                canInspect: canInspectTransaction(item)
                            )

                            Divider()
                                .overlay(CosignTheme.line)
                                .padding(.leading, 14)
                        }

                        CosignObjectNavigationLink(value: Route.activity(squad: squadAddress)) {
                            CosignObjectRow(
                                title: CosignCopy.Activity.allActivityTitle,
                                style: .plain,
                                leading: {
                                    CosignGlyphView(glyph: .clock, size: 18, color: CosignTheme.accentDeep)
                                        .frame(width: 36, height: 36)
                                }
                            )
                        }
                    }
                }
            }
        }
        .task(id: squadAddress) {
            await load()
        }
        .pollingRefresh(
            id: "activity-preview-\(squadAddress)",
            interval: ReadPollingInterval.activity,
            enabled: !squadAddress.isEmpty
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
        .webSocketRefresh(
            id: "activity-preview-\(squadAddress)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: [squadAddress],
            enabled: !squadAddress.isEmpty
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
    }

    private var displayedItems: [SquadActivityItem] {
        items.filter { selectedFilter.includes($0) }
    }

    private var filterIndexBinding: Binding<Int> {
        Binding(
            get: { ActivityFilter.allCases.firstIndex(of: selectedFilter) ?? 0 },
            set: { selectedFilter = ActivityFilter.allCases[$0] }
        )
    }

    @MainActor
    private func load(forceRefresh: Bool = false, showsLoading: Bool = true) async {
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
            items = if forceRefresh {
                try await squadsService.refreshActivity(in: squadAddress, before: nil, limit: 5)
            } else {
                try await squadsService.activity(in: squadAddress, before: nil, limit: 5)
            }
            errorMessage = nil
        } catch {
            if items.isEmpty {
                errorMessage = String(describing: error)
            }
        }
    }

    private var emptyActivityPreview: some View {
        CosignEmptyState(key: .emptyActivity)
    }

    private func canInspectTransaction(_ item: SquadActivityItem) -> Bool {
        let request = ExecutedTransactionInspectionRequest(signature: item.signature)
        return indexerEnvironment.relay.executedTransactionInspectionURL(for: request) != nil
    }
}
