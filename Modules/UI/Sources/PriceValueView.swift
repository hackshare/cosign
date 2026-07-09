import Squads
import SwiftUI

/// Freshness-aware USD value and optional 24h delta for a holdings row trailing
/// column.
///
/// Freshness ladder:
/// - fresh: USD in primary ink + delta below in full color.
/// - stale: USD in secondary ink + amber dot + age label + dimmed delta.
/// - expired + usd non-nil: "Price unavailable" in tertiary ink, no delta.
/// - expired + usd nil, or usd nil at any freshness: em-dash (no price data).
///
/// Callers suppress "Price unavailable" when the whole-feed expired banner
/// already communicates the state by passing usd: nil for expired rows.
struct PriceValueView: View {
    let usd: Double?
    let change24h: Double?
    let freshness: PriceFreshness

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch freshness {
            case .fresh:
                if let usd {
                    usdLabel(formatLiveUSD(usd), color: CosignTheme.ink)
                    deltaLabel(change24h, dimmed: false)
                } else {
                    emDash
                }

            case let .stale(minutesOld):
                if let usd {
                    HStack(spacing: 4) {
                        usdLabel(formatLiveUSD(usd), color: CosignTheme.inkDim)
                        Circle()
                            .fill(CosignTheme.riskAmber)
                            .frame(width: 5, height: 5)
                        Text(CosignCopy.VaultDetail.minutesOld(minutesOld))
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkFaint)
                    }
                    deltaLabel(change24h, dimmed: true)
                } else {
                    emDash
                }

            case .expired:
                if usd != nil {
                    Text(CosignCopy.VaultDetail.priceUnavailable)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkFaint)
                } else {
                    emDash
                }
            }
        }
    }

    private func usdLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(CosignTheme.FontStyle.body)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .monospacedDigit()
    }

    private var emDash: some View {
        Text(CosignCopy.VaultDetail.usdUnavailable)
            .font(CosignTheme.FontStyle.body)
            .foregroundStyle(CosignTheme.inkDim)
            .monospacedDigit()
    }

    @ViewBuilder
    private func deltaLabel(_ pct: Double?, dimmed: Bool) -> some View {
        if let pct {
            Text(CosignCopy.VaultDetail.priceChange24h(pct))
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(deltaColor(pct))
                .monospacedDigit()
                .opacity(dimmed ? 0.55 : 1.0)
        }
    }

    private func deltaColor(_ pct: Double) -> Color {
        let formatted = String(format: "%.1f", Swift.abs(pct))
        if formatted == "0.0" {
            return CosignTheme.inkFaint
        }
        return pct > 0 ? CosignTheme.mint : CosignTheme.riskRed
    }
}
