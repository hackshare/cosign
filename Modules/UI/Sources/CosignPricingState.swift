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
