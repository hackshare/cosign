import Indexer
import Squads
import SwiftUI

public struct VaultInspectionView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.cosignDemoMode) private var demoMode
    @Environment(\.indexerEnvironment) private var indexerEnvironment
    @Environment(\.openURL) private var openURL
    @Environment(\.squadsService) private var squadsService

    private let squadAddress: String
    private let vaultIndex: UInt8
    private let activityLimit: UInt32 = 5

    @State private var detail: SquadDetail?
    @State private var vault: VaultDetail?
    @State private var activityItems = [SquadActivityItem]()
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var copiedVaultAddress = false
    @State private var prices: [String: Double]?

    public init(squadAddress: String, vaultIndex: UInt8) {
        self.squadAddress = squadAddress
        self.vaultIndex = vaultIndex
    }

    public var body: some View {
        Group {
            if let detail, let vault {
                content(detail: detail, vault: vault)
            } else if isLoading {
                CosignScreen {
                    navigationHeader()
                    CosignLoadingCard()
                }
            } else if let errorMessage {
                CosignScreen {
                    navigationHeader()
                    CosignEmptyState(
                        title: CosignCopy.VaultInspection.unableToLoadTitle,
                        systemImage: "exclamationmark.triangle",
                        message: errorMessage
                    )
                }
            } else {
                CosignScreen {
                    navigationHeader()
                    CosignLoadingCard()
                }
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignPage()
        .refreshable { await load(forceRefresh: true) }
        .task(id: "\(squadAddress)-\(vaultIndex)") { await load() }
        .pollingRefresh(
            id: "vault-inspection-\(squadAddress)-\(vaultIndex)",
            interval: ReadPollingInterval.detail,
            enabled: !squadAddress.isEmpty
        ) { await load(forceRefresh: true, showsLoading: false) }
        .webSocketRefresh(
            id: "vault-inspection-\(squadAddress)-\(vaultIndex)",
            webSocketURL: indexerEnvironment.effectiveWebSocketURL,
            accounts: watchedAccounts,
            enabled: vault != nil
        ) { await load(forceRefresh: true, showsLoading: false) }
        .accessibilityIdentifier("screen.vault-inspection")
    }

    private func content(detail: SquadDetail, vault: VaultDetail) -> some View {
        CosignScreen {
            navigationHeader(vault)
            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.VaultInspection.header(
                    squadName: displayName(for: detail),
                    vaultIndex: vault.ref.index
                ))
                Text(CosignCopy.VaultInspection.navigationTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.VaultInspection.vaultSubtitle(address: cosignShortAddress(vault.ref.address)))
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.inkFaint)
            }
            identitySection(detail: detail, vault: vault)
            movementSection(vault: vault)
            explorerActions(vault)
            holdingsSection(vault)
        }
    }

    private func navigationHeader(_ vault: VaultDetail? = nil) -> some View {
        CosignCompactPageHeader(title: CosignCopy.VaultInspection.navigationTitle) {
            coordinator.pop()
        } accessory: {
            if let vault {
                CosignPlainGlyphButton(
                    glyph: .external,
                    accessibilityLabel: CosignCopy.VaultDetail.openInExplorerAccessibilityLabel
                ) {
                    openVaultInExplorer(vault)
                }
            }
        }
    }

    private func identitySection(detail: SquadDetail, vault: VaultDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.VaultInspection.identitySection)
            CosignCard(padding: 0) {
                VStack(spacing: 0) {
                    CosignKeyValueRow(
                        label: CosignCopy.VaultInspection.authorityLabel,
                        value: displayName(for: detail),
                        detail: "\(cosignShortAddress(detail.address)) · \(CosignCopy.Squads.threshold(detail.threshold, memberCount: detail.members.count))"
                    )
                    CosignKeyValueRow(
                        label: CosignCopy.VaultInspection.holdingsLabel,
                        value: holdingsValue(vault),
                        detail: holdingsDetail(vault),
                        isLast: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func holdingsSection(_ vault: VaultDetail) -> some View {
        let vaultTokens = tokens(in: vault)
        let vaultNFTs = nfts(in: vault)

        if vault.nativeBalanceLamports == nil, vaultTokens.isEmpty, vaultNFTs.isEmpty {
            CosignEmptyState(key: .emptyTokens)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(
                    title: CosignCopy.VaultDetail.holdingsTitle(
                        assetCount: vaultTokens.count + vaultNFTs.count + (vault.nativeBalanceLamports == nil ? 0 : 1)
                    ),
                    trailing: demoMode == nil ? nil : CosignCopy.VaultDetail.usdValueColumn
                )
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        if let nativeBalanceLamports = vault.nativeBalanceLamports {
                            NativeTokenRow(
                                lamports: nativeBalanceLamports,
                                trailingValue: usdValueText(lamports: nativeBalanceLamports, prices: prices)
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }

                        ForEach(Array(vaultTokens.enumerated()), id: \.element.id) { index, asset in
                            if index > 0 || vault.nativeBalanceLamports != nil {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                            FungibleAssetRow(
                                asset: asset,
                                trailingValue: usdValueText(asset: asset, prices: prices)
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }

                        ForEach(Array(vaultNFTs.enumerated()), id: \.element.id) { index, asset in
                            if index > 0 || !vaultTokens.isEmpty || vault.nativeBalanceLamports != nil {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                            NFTAssetRow(asset: asset)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    private func movementSection(vault: VaultDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.VaultInspection.recentMovementSection)
            if isLoading, activityItems.isEmpty {
                CosignLoadingCard()
            } else if activityItems.isEmpty {
                CosignEmptyState(
                    title: CosignCopy.VaultInspection.noRecentMovementTitle,
                    systemImage: "clock.arrow.circlepath",
                    message: CosignCopy.VaultInspection.noRecentMovementMessage
                )
            } else {
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(activityItems.enumerated()), id: \.element.id) { index, item in
                            movementRow(item, vaultAddress: vault.ref.address)

                            if index < activityItems.count - 1 {
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

    private func explorerActions(_ vault: VaultDetail) -> some View {
        HStack(spacing: 12) {
            Button {
                copyVaultAddress(vault.ref.address)
            } label: {
                HStack(spacing: 8) {
                    CosignGlyphView(glyph: copiedVaultAddress ? .check : .copy, size: 16)
                    Text(copiedVaultAddress ? CosignCopy.Common.copied : CosignCopy.VaultInspection.copyAddress)
                }
                .frame(maxWidth: .infinity)
            }
            .cosignSecondaryAction()
            .buttonStyle(.plain)

            Button {
                openVaultInExplorer(vault)
            } label: {
                HStack(spacing: 8) {
                    CosignGlyphView(glyph: .external, size: 16)
                    Text(CosignCopy.VaultInspection.openInExplorer)
                }
                .frame(maxWidth: .infinity)
            }
            .cosignSecondaryAction()
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func movementRow(_ item: SquadActivityItem, vaultAddress: String) -> some View {
        let row = VaultMovementRow(
            item: item,
            vaultAddress: vaultAddress,
            showsChevron: canInspectTransaction(item)
        )
        if canInspectTransaction(item) {
            CosignObjectNavigationLink(value: Route.transactionInspection(
                signature: item.signature,
                squad: squadAddress
            )) {
                row
            }
        } else {
            row
        }
    }
}

private extension VaultInspectionView {
    var watchedAccounts: [String] {
        guard let vault else {
            return []
        }

        return [vault.ref.address] + vault.assets.compactMap(\.accountAddress)
    }

    @MainActor
    func load(forceRefresh: Bool = false, showsLoading: Bool = true) async {
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
                self.detail = detail
                vault = nil
                errorMessage = CosignCopy.VaultDetail.missingVaultMessage(index: vaultIndex)
                return
            }
            self.detail = detail
            self.vault = vault
            if demoMode == nil {
                prices = await squadsService.prices(for: [cosignWrappedSolMint] + vault.assets.map(\.id))
            }
            activityItems = try await squadsService.activity(
                forAddress: vault.ref.address,
                before: nil,
                limit: activityLimit
            )
            errorMessage = nil
        } catch {
            if vault == nil {
                errorMessage = String(describing: error)
            }
        }
    }

    func displayName(for detail: SquadDetail) -> String {
        detail.displayName ?? CosignCopy.SquadDetail.navigationTitle
    }

    func holdingsValue(_ vault: VaultDetail) -> String {
        CosignCopy.VaultInspection.holdingsValue(
            sol: vault.nativeBalanceLamports.map(solQuantity) ?? CosignCopy.SquadDetail.unavailable,
            tokenCount: tokens(in: vault).count
        )
    }

    func holdingsDetail(_ vault: VaultDetail) -> String? {
        let symbols = tokens(in: vault)
            .compactMap { $0.symbol ?? $0.name }
            .prefix(4)
        let value = symbols.joined(separator: " · ")
        return value.isEmpty ? nil : value
    }

    func canInspectTransaction(_ item: SquadActivityItem) -> Bool {
        let request = ExecutedTransactionInspectionRequest(signature: item.signature)
        return indexerEnvironment.relay.executedTransactionInspectionURL(for: request) != nil
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
