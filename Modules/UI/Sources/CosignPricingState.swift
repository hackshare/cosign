import SwiftUI

/// Shown when live USD prices aren't available yet (or the relay's pricing
/// add-on didn't answer). The app always prices through the relay, so there is
/// no relay-vs-RPC distinction to surface.
struct CosignPricingNotice: View {
    init() {}

    var body: some View {
        CosignInlineBanner(tone: .neutral) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CosignCopy.Pricing.relayNoQuotesTitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.Pricing.relayPricingPendingMessage)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkDim)
            }
        }
    }
}

/// Shown when the entire price feed is expired (>15 min since last fetch).
/// Replaces per-row "Price unavailable" text — the banner communicates the
/// whole-feed state so individual rows show em-dashes instead.
struct CosignPricesExpiredBanner: View {
    var body: some View {
        CosignInlineBanner(tone: .amber) {
            Text(CosignCopy.VaultDetail.pricesUnavailableBannerTitle)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.ink)
        }
    }
}
