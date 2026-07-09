import Indexer
import Squads
import SwiftUI

extension VaultDetailView {
    /// Token holdings section with freshness-aware USD trailing values.
    @ViewBuilder
    func tokensSection(_ vault: VaultDetail, freshness: PriceFreshness) -> some View {
        let vaultTokens = tokens(in: vault)
        if vaultTokens.isEmpty, vault.nativeBalanceLamports == nil {
            CosignEmptyState(key: .emptyTokens)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(
                    title: CosignCopy.VaultDetail.holdingsTitle(
                        assetCount: vaultTokens.count + (vault.nativeBalanceLamports == nil ? 0 : 1)
                    ),
                    trailing: CosignCopy.VaultDetail.usdValueColumn
                )
                VStack(spacing: 0) {
                    if let nativeBalanceLamports = vault.nativeBalanceLamports {
                        NativeTokenRow(lamports: nativeBalanceLamports) {
                            vaultHoldingsPriceView(
                                usd: vaultSOLUSDValue(lamports: nativeBalanceLamports, freshness: freshness),
                                change24h: vaultLiveChange24h(for: cosignWrappedSolMint, freshness: freshness),
                                freshness: freshness
                            )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    ForEach(Array(vaultTokens.enumerated()), id: \.element.id) { index, asset in
                        if index > 0 || vault.nativeBalanceLamports != nil {
                            Divider()
                                .overlay(CosignTheme.line)
                                .padding(.leading, 14)
                        }
                        FungibleAssetRow(asset: asset) {
                            vaultHoldingsPriceView(
                                usd: vaultAssetUSDValue(asset: asset, freshness: freshness),
                                change24h: vaultLiveChange24h(for: asset.id, freshness: freshness),
                                freshness: freshness
                            )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }

                if vaultTokens.isEmpty {
                    CosignEmptyState(key: .emptyTokens)
                }
            }
        }
    }

    // MARK: - Holdings price helpers

    private func isGlobalExpired(_ freshness: PriceFreshness) -> Bool {
        freshness.isExpired
    }

    func vaultSOLUSDValue(lamports: UInt64, freshness: PriceFreshness) -> Double? {
        guard !isGlobalExpired(freshness), let snapshot = priceSnapshot else { return nil }
        return usdValue(lamports: lamports, snapshot: snapshot)
    }

    func vaultAssetUSDValue(asset: DASAsset, freshness: PriceFreshness) -> Double? {
        guard !isGlobalExpired(freshness), let snapshot = priceSnapshot else { return nil }
        return usdValue(asset: asset, snapshot: snapshot)
    }

    func vaultLiveChange24h(for mint: String, freshness: PriceFreshness) -> Double? {
        guard !isGlobalExpired(freshness) else { return nil }
        return priceSnapshot?.change24h(for: mint)
    }

    func vaultHoldingsPriceView(usd: Double?, change24h: Double?, freshness: PriceFreshness) -> some View {
        PriceValueView(usd: usd, change24h: change24h, freshness: freshness)
    }
}
