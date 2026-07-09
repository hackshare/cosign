import Indexer
import Squads
import SwiftUI

public struct SquadDetailView: View {
    @Environment(Coordinator.self) var coordinator
    @Environment(\.cosignDemoMode) var demoMode
    @Environment(\.indexerEnvironment) var indexerEnvironment
    @Environment(\.squadsService) private var squadsService

    private let squadAddress: String

    @State private var detail: SquadDetail?
    @State var priceSnapshot: PriceSnapshot?
    @State private var selectedTab: SquadDetailTab = .vaults
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(squadAddress: String) {
        self.squadAddress = squadAddress
    }

    public var body: some View {
        Group {
            if let detail {
                detailContent(detail)
            } else if isLoading {
                CosignScreen {
                    squadNavigationHeader()
                    CosignLoadingCard()
                }
            } else if let errorMessage {
                CosignScreen {
                    squadNavigationHeader()
                    CosignEmptyState(
                        title: CosignCopy.SquadDetail.unableToLoadSquadTitle,
                        systemImage: "exclamationmark.triangle",
                        message: errorMessage
                    )
                }
            } else {
                CosignScreen {
                    squadNavigationHeader()
                    CosignLoadingCard()
                }
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignPage()
        .refreshable {
            await load(forceRefresh: true)
        }
        .task(id: squadAddress) {
            await load()
        }
        .onAppear {
            guard detail != nil else {
                return
            }
            Task {
                await load(forceRefresh: true, showsLoading: false)
            }
        }
        .pollingRefresh(
            id: "squad-detail-\(squadAddress)",
            interval: ReadPollingInterval.detail,
            enabled: !squadAddress.isEmpty
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
        .webSocketRefresh(
            id: "squad-detail-\(squadAddress)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: watchedAccounts,
            enabled: detail != nil
        ) {
            await load(forceRefresh: true, showsLoading: false)
        }
        .accessibilityIdentifier("screen.squad-detail")
    }

    private func detailContent(_ detail: SquadDetail) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let freshness = priceSnapshot?.freshness(now: context.date)
            CosignScreen {
                squadNavigationHeader(detail)
                squadHeader(detail)
                if !detail.vaults.isEmpty {
                    squadAssetCard(detail)
                    pricingNotice(freshness: freshness, for: detail)
                    squadMetadataCard(detail)
                }

                CosignSegmentedTabs(
                    tabs: SquadDetailTab.allCases,
                    selection: $selectedTab,
                    style: .underline,
                    title: \.title
                )

                switch selectedTab {
                case .vaults:
                    vaultsSection(detail, freshness: freshness)
                case .proposals:
                    proposalsSection(detail)
                case .activity:
                    activitySection(detail)
                case .members:
                    membersSection(detail)
                }
            }
        }
    }

    private func squadNavigationHeader(_ detail: SquadDetail? = nil) -> some View {
        CosignCompactPageHeader {
            coordinator.pop()
        } accessory: {
            if let detail {
                CosignIconButton(glyph: .copy) {
                    copyToPasteboard(detail.address)
                }
                .accessibilityLabel(CosignCopy.Squads.copySquadAddress)
            }
        }
    }

    private func squadHeader(_ detail: SquadDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CosignSectionTitle(title: CosignCopy.SquadDetail.header(
                threshold: detail.threshold,
                memberCount: detail.members.count
            ))
            Text(detail.displayName ?? cosignMediumAddress(detail.address))
                .font(CosignTheme.FontStyle.display)
                .foregroundStyle(CosignTheme.ink)

            HStack(spacing: 8) {
                Text(squadHeaderSubtitle(detail))
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.inkDim)
                    .lineLimit(1)
                Button {
                    copyToPasteboard(detail.address)
                } label: {
                    CosignGlyphView(glyph: .copy, size: 14, color: CosignTheme.inkGhost)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func vaultsSection(_ detail: SquadDetail, freshness: PriceFreshness?) -> some View {
        if detail.vaults.count == 1, let vault = detail.vaults.first {
            singleVaultSection(vault, freshness: freshness)
        } else {
            VaultsListView(squadAddress: detail.address, vaults: detail.vaults) {
                selectedTab = .members
            }
        }
    }

    private func singleVaultSection(_ vault: VaultDetail, freshness: PriceFreshness?) -> some View {
        SingleVaultDetailSection(
            squadAddress: squadAddress,
            vault: vault,
            priceSnapshot: priceSnapshot,
            freshness: freshness ?? .fresh
        )
    }

    private func proposalsSection(_ detail: SquadDetail) -> some View {
        ProposalsPreviewSection(
            squadAddress: detail.address,
            latestTransactionIndex: detail.transactionIndex
        ) {
            selectedTab = .activity
        }
    }

    private func activitySection(_ detail: SquadDetail) -> some View {
        ActivityPreviewSection(squadAddress: detail.address)
    }

    private var watchedAccounts: [String] {
        guard let detail else {
            return []
        }

        return [detail.address] + detail.vaults.flatMap { vault in
            [vault.ref.address] + vault.assets.compactMap(\.accountAddress)
        }
    }

    @MainActor
    private func load(forceRefresh: Bool = false, showsLoading: Bool = true) async {
        guard !squadAddress.isEmpty else {
            errorMessage = CosignCopy.SquadDetail.emptySquadAddressMessage
            detail = nil
            return
        }

        if showsLoading {
            isLoading = true
        }
        if detail == nil || showsLoading {
            errorMessage = nil
        }
        defer {
            if showsLoading {
                isLoading = false
            }
        }

        do {
            let loaded = if forceRefresh {
                try await squadsService.refreshDetail(of: squadAddress)
            } else {
                try await squadsService.detail(of: squadAddress)
            }
            detail = loaded
            let mints = [cosignWrappedSolMint] + loaded.vaults.flatMap { $0.assets.map(\.id) }
            var snapshot = await squadsService.priceSnapshot(for: Array(Set(mints)))
            #if DEBUG
            if let ageSeconds = CosignDemoMode.priceAgeSeconds(), demoMode != nil {
                let shiftedAt = snapshot.fetchedAt.addingTimeInterval(-Double(ageSeconds))
                snapshot = PriceSnapshot(prices: snapshot.prices, changes: snapshot.changes, fetchedAt: shiftedAt)
            }
            #endif
            priceSnapshot = snapshot
            errorMessage = nil
        } catch {
            if detail == nil {
                errorMessage = String(describing: error)
            }
        }
    }
}

private extension SquadDetailView {
    func squadHeaderSubtitle(_ detail: SquadDetail) -> String {
        let address = cosignShortAddress(detail.address, prefix: 4, suffix: 4)
        return "\(address) · \(CosignCopy.SquadDetail.vaultCount(detail.vaults.count))"
            + " · \(CosignCopy.SquadDetail.memberCount(detail.members.count))"
    }
}
