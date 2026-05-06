import Indexer
import Squads
import SwiftUI

public struct VaultDetailView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.cosignDemoMode) private var demoMode
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
    @State private var prices: [String: Double]?

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
        CosignScreen {
            vaultNavigationHeader(vault)
            vaultHeader(vault)
            vaultBalanceHero(vault)
            pricingNotice(for: vault)
            vaultQuickActions(vault)

            CosignSegmentedTabs(
                tabs: VaultAssetTab.allCases,
                selection: $selectedTab,
                style: .underline,
                title: \.title
            )

            switch selectedTab {
            case .tokens:
                tokensSection(vault)
            case .nfts:
                nftsSection(vault)
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

    private func vaultBalanceHero(_ vault: VaultDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CosignCopy.VaultDetail.balance.uppercased())
                .font(CosignTheme.FontStyle.eyebrow)
                .foregroundStyle(CosignTheme.inkFaint)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CosignAmountText(
                    amount: vault.nativeBalanceLamports.map(solQuantity) ?? CosignCopy.SquadDetail.unavailable,
                    size: 48
                )
                .minimumScaleFactor(0.58)
                .lineLimit(1)
                if vault.nativeBalanceLamports != nil {
                    Text(CosignCopy.Vaults.solSymbol)
                        .font(CosignTheme.FontStyle.titleL)
                        .foregroundStyle(CosignTheme.inkDim)
                        .baselineOffset(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let estimatedUSD = vaultEstimatedUSD(vault) {
                Text(estimatedUSD)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
            }
        }
    }

    @ViewBuilder
    private func pricingNotice(for vault: VaultDetail) -> some View {
        if demoMode == nil, prices == nil, vault.nativeBalanceLamports != nil || !vault.assets.isEmpty {
            CosignPricingNotice()
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
    @ViewBuilder
    func tokensSection(_ vault: VaultDetail) -> some View {
        let tokens = tokens(in: vault)
        if tokens.isEmpty, vault.nativeBalanceLamports == nil {
            CosignEmptyState(key: .emptyTokens)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(
                    title: CosignCopy.VaultDetail.holdingsTitle(
                        assetCount: tokens.count + (vault.nativeBalanceLamports == nil ? 0 : 1)
                    ),
                    trailing: CosignCopy.VaultDetail.usdValueColumn
                )
                VStack(spacing: 0) {
                    if let nativeBalanceLamports = vault.nativeBalanceLamports {
                        NativeTokenRow(
                            lamports: nativeBalanceLamports,
                            trailingValue: usdTrailing(usdValueText(lamports: nativeBalanceLamports, prices: prices))
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    ForEach(Array(tokens.enumerated()), id: \.element.id) { index, asset in
                        if index > 0 || vault.nativeBalanceLamports != nil {
                            Divider()
                                .overlay(CosignTheme.line)
                                .padding(.leading, 14)
                        }
                        FungibleAssetRow(
                            asset: asset,
                            trailingValue: usdTrailing(usdValueText(asset: asset, prices: prices))
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }

                if tokens.isEmpty {
                    CosignEmptyState(key: .emptyTokens)
                }
            }
        }
    }

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
            await loadPrices(for: vault)
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

    /// Live USD prices for the vault's mints. Demo builds keep their illustrative
    /// model (prices stays nil → demo fallback in the USD helpers).
    private func loadPrices(for vault: VaultDetail) async {
        guard demoMode == nil else {
            return
        }
        let mints = [cosignWrappedSolMint] + vault.assets.map(\.id)
        prices = await squadsService.prices(for: mints)
    }

    func vaultEstimatedUSD(_ vault: VaultDetail) -> String? {
        guard let nativeBalanceLamports = vault.nativeBalanceLamports else {
            return nil
        }
        return estimatedUSDText(lamports: nativeBalanceLamports, prices: prices)
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
