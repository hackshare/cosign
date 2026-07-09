import Squads
import SwiftUI

extension VaultDetailView {
    /// Vault balance hero: SOL amount (large) + freshness-aware USD + 24h delta.
    ///
    /// Parameters are passed explicitly so this extension does not need direct
    /// access to private state properties.
    func vaultBalanceHero(_ vault: VaultDetail, freshness: PriceFreshness?) -> some View {
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

            heroUSDSection(vault, freshness: freshness ?? .fresh)
        }
    }

    /// USD + delta section below the SOL amount. Uses the same freshness ladder
    /// as holdings rows but with the hero's "≈ $X.XX USD" format.
    @ViewBuilder
    func heroUSDSection(_ vault: VaultDetail, freshness: PriceFreshness) -> some View {
        if let nativeLamports = vault.nativeBalanceLamports {
            let solUSD = heroSOLUSD(lamports: nativeLamports, freshness: freshness)
            let change24h = heroChange24h(freshness: freshness)
            heroFreshnessTreatment(freshness, solUSD: solUSD, change24h: change24h)
        }
    }

    private func heroSOLUSD(lamports: UInt64, freshness: PriceFreshness) -> Double? {
        guard !freshness.isExpired, let snapshot = priceSnapshot else { return nil }
        return usdValue(lamports: lamports, snapshot: snapshot)
    }

    private func heroChange24h(freshness: PriceFreshness) -> Double? {
        guard !freshness.isExpired else { return nil }
        return priceSnapshot?.change24h(for: cosignWrappedSolMint)
    }

    @ViewBuilder
    private func heroFreshnessTreatment(
        _ freshness: PriceFreshness,
        solUSD: Double?,
        change24h: Double?
    ) -> some View {
        switch freshness {
        case .fresh:
            if let solUSD {
                Text(CosignCopy.SquadDetail.estimatedUSD(formatLiveUSD(solUSD)))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                heroDeltaLine(change24h, opacity: 1.0)
            }

        case let .stale(minutesOld):
            if let solUSD {
                HStack(spacing: 4) {
                    Text(CosignCopy.SquadDetail.estimatedUSD(formatLiveUSD(solUSD)))
                        .font(CosignTheme.FontStyle.monoSmall)
                        .foregroundStyle(CosignTheme.inkDim)
                    Circle()
                        .fill(CosignTheme.riskAmber)
                        .frame(width: 5, height: 5)
                    Text(CosignCopy.VaultDetail.minutesOld(minutesOld))
                        .font(CosignTheme.FontStyle.monoSmall)
                        .foregroundStyle(CosignTheme.inkFaint)
                }
                heroDeltaLine(change24h, opacity: 0.55)
            }

        case .expired:
            Text(CosignCopy.VaultDetail.priceUnavailable)
                .font(CosignTheme.FontStyle.monoSmall)
                .foregroundStyle(CosignTheme.inkFaint)
        }
    }

    @ViewBuilder
    private func heroDeltaLine(_ pct: Double?, opacity: Double) -> some View {
        if let pct {
            Text(CosignCopy.VaultDetail.priceChange24h(pct))
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(heroDeltaColor(pct))
                .monospacedDigit()
                .opacity(opacity)
        }
    }

    private func heroDeltaColor(_ pct: Double) -> Color {
        let formatted = String(format: "%.1f", Swift.abs(pct))
        if formatted == "0.0" { return CosignTheme.inkFaint }
        return pct > 0 ? CosignTheme.mint : CosignTheme.riskRed
    }
}
