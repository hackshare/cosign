import Indexer
import Squads
import SwiftUI

public struct VaultDetailView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.cosignDemoMode) var demoMode
    @Environment(\.indexerEnvironment) private var indexerEnvironment
    @Environment(\.openURL) private var openURL
    @Environment(\.squadsService) private var squadsService

    private let squadAddress: String
    private let vaultIndex: UInt8

    @State private var vault: VaultDetail?
    @State private var selectedTab: VaultAssetTab = .tokens
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var copiedVaultAddress = false
    @State private var squadDisplayName: String?
    @State var priceSnapshot: PriceSnapshot?

    public init(squadAddress: String, vaultIndex: UInt8) {
        self.squadAddress = squadAddress
        self.vaultIndex = vaultIndex
    }

    public var body: some View {
        Group {
            if let vault {
                vaultContent(vault)
            } else if isLoading {
                CosignScreen {
                    vaultNavigationHeader()
                    CosignLoadingCard()
                }
            } else if let errorMessage {
                CosignScreen {
                    vaultNavigationHeader()
                    CosignEmptyState(
                        title: CosignCopy.VaultDetail.unableToLoadVaultTitle,
                        systemImage: "exclamationmark.triangle",
                        message: errorMessage
                    )
                }
            } else {
                CosignScreen {
                    CosignLoadingCard()
                }
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignPage()
        .refreshable { await load(forceRefresh: true) }
        .task(id: "\(squadAddress)-\(vaultIndex)") { await load() }
        .onAppear {
            guard vault != nil else { return }
            Task { await load(forceRefresh: true, showsLoading: false) }
        }
        .pollingRefresh(
            id: "vault-detail-\(squadAddress)-\(vaultIndex)",
            interval: ReadPollingInterval.detail,
            enabled: !squadAddress.isEmpty
        ) { await load(forceRefresh: true, showsLoading: false) }
        .webSocketRefresh(
            id: "vault-detail-\(squadAddress)-\(vaultIndex)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: watchedAccounts,
            enabled: vault != nil
        ) { await load(forceRefresh: true, showsLoading: false) }
        .accessibilityIdentifier("screen.vault-detail")
    }

    private func vaultContent(_ vault: VaultDetail) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let freshness = priceSnapshot?.freshness(now: context.date)
            CosignScreen {
                vaultNavigationHeader(vault)
                vaultHeader(vault)
                vaultBalanceHero(vault, freshness: freshness)
                pricingNotice(for: vault, freshness: freshness)
                vaultQuickActions(vault)

                CosignSegmentedTabs(
                    tabs: VaultAssetTab.allCases,
                    selection: $selectedTab,
                    style: .underline,
                    title: \.title
                )

                switch selectedTab {
                case .tokens:
                    tokensSection(vault, freshness: freshness ?? .fresh)
                case .nfts:
                    nftsSection(vault)
                }
            }
        }
    }

    private func vaultNavigationHeader(_ vault: VaultDetail? = nil) -> some View {
        CosignCompactPageHeader {
            coordinator.pop()
        } accessory: {
            if let vault {
                HStack(spacing: 8) {
                    CosignPlainGlyphButton(
                        glyph: .copy,
                        accessibilityLabel: CosignCopy.Vaults.copyVaultAddress
                    ) {
                        copyVaultAddress(vault.ref.address)
                    }

                    CosignPlainGlyphButton(
                        glyph: .external,
                        accessibilityLabel: CosignCopy.VaultDetail.openInExplorerAccessibilityLabel
                    ) {
                        openVaultInExplorer(vault)
                    }
                }
            }
        }
    }

    private func vaultHeader(_ vault: VaultDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CosignSectionTitle(title: vaultHeaderTitle(vault))
            ZStack(alignment: .leading) {
                Text(cosignShortAddress(vault.ref.address, prefix: 4, suffix: 4))
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(CosignTheme.inkDim)
                    .lineLimit(1)
                    .opacity(copiedVaultAddress ? 0 : 1)
                if copiedVaultAddress {
                    CosignCopiedValueFeedback(value: vault.ref.address)
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func pricingNotice(for vault: VaultDetail, freshness: PriceFreshness?) -> some View {
        if demoMode == nil, vault.nativeBalanceLamports != nil || !vault.assets.isEmpty {
            if let freshness {
                if freshness.isExpired {
                    CosignPricesExpiredBanner()
                } else if priceSnapshot?.prices.isEmpty == true {
                    CosignPricingNotice()
                }
            } else {
                CosignPricingNotice()
            }
        }
    }

    private func vaultQuickActions(_ vault: VaultDetail) -> some View {
        HStack(spacing: 12) {
            vaultActionButton(
                title: CosignCopy.VaultDetail.propose,
                glyph: .plus,
                accessibilityIdentifier: "vault-action-propose"
            ) {
                coordinator.go(to: .createTransferProposal(
                    squad: squadAddress,
                    vaultIndex: vault.ref.index
                ))
            }

            vaultActionButton(
                title: CosignCopy.VaultDetail.inspect,
                glyph: .search,
                accessibilityIdentifier: "vault-action-inspect"
            ) {
                coordinator.go(to: .vaultInspection(squad: squadAddress, vaultIndex: vault.ref.index))
            }

            vaultActionButton(
                title: CosignCopy.VaultDetail.history,
                glyph: .clock,
                accessibilityIdentifier: "vault-action-history"
            ) {
                coordinator.go(to: .activity(squad: squadAddress))
            }
        }
    }

    private func vaultActionButton(
        title: String,
        glyph: CosignGlyph,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                CosignGlyphView(
                    glyph: glyph,
                    size: 16,
                    color: CosignTheme.ink
                )
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(
                CosignTheme.surface,
                in: .rect(cornerRadius: CosignTheme.Radius.medium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                    .stroke(CosignTheme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private extension VaultDetailView {
    var watchedAccounts: [String] {
        guard let vault else {
            return []
        }

        return [vault.ref.address] + vault.assets.compactMap(\.accountAddress)
    }

    @MainActor
    func load(forceRefresh: Bool = false, showsLoading: Bool = true) async {
        guard !squadAddress.isEmpty else {
            errorMessage = "The Squad address is empty."
            vault = nil
            return
        }

        if showsLoading {
            isLoading = true
        }
        if vault == nil || showsLoading {
            errorMessage = nil
        }
        defer {
            if showsLoading {
                isLoading = false
            }
        }

        do {
            let detail = if forceRefresh {
                try await squadsService.refreshDetail(of: squadAddress)
            } else {
                try await squadsService.detail(of: squadAddress)
            }
            guard let vault = detail.vaults.first(where: { $0.ref.index == vaultIndex }) else {
                vault = nil
                errorMessage = CosignCopy.VaultDetail.missingVaultMessage(index: vaultIndex)
                return
            }
            self.vault = vault
            squadDisplayName = detail.displayName
            errorMessage = nil
            await loadPriceSnapshot(for: vault)
        } catch {
            if vault == nil {
                errorMessage = String(describing: error)
            }
        }
    }

    func vaultHeaderTitle(_ vault: VaultDetail) -> String {
        CosignCopy.VaultDetail.header(
            squadName: squadDisplayName ?? CosignCopy.SquadDetail.navigationTitle,
            vaultIndex: vault.ref.index
        )
    }

    private func loadPriceSnapshot(for vault: VaultDetail) async {
        let mints = [cosignWrappedSolMint] + vault.assets.map(\.id)
        var snapshot = await squadsService.priceSnapshot(for: mints)
        #if DEBUG
        if let ageSeconds = CosignDemoMode.priceAgeSeconds(), demoMode != nil {
            let shiftedAt = snapshot.fetchedAt.addingTimeInterval(-Double(ageSeconds))
            snapshot = PriceSnapshot(prices: snapshot.prices, changes: snapshot.changes, fetchedAt: shiftedAt)
        }
        #endif
        priceSnapshot = snapshot
    }

    func openVaultInExplorer(_ vault: VaultDetail) {
        guard let url = SolanaExplorer.addressURL(
            address: vault.ref.address,
            rpcURL: indexerEnvironment.effectiveExplorerRPCURL
        ) else {
            return
        }
        openURL(url)
    }

    func copyVaultAddress(_ address: String) {
        copyToPasteboard(address)
        copiedVaultAddress = true
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            await MainActor.run {
                copiedVaultAddress = false
            }
        }
    }
}
