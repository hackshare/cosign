import Squads
import SwiftUI

extension SquadDetailView {
    /// Shows a pricing status banner when needed:
    /// - Snapshot not yet loaded: "no quotes" pending notice.
    /// - Relay returned empty prices (not expired): "no quotes" pending notice.
    /// - Whole feed expired: "Prices unavailable" amber banner. This replaces
    ///   per-value "Price unavailable" text — see PriceValueView call sites.
    /// - Demo mode or prices loaded and fresh/stale: nothing shown here.
    @ViewBuilder
    func pricingNotice(freshness: PriceFreshness?, for detail: SquadDetail) -> some View {
        if demoMode == nil, assetSummary(for: detail).hasPriceableHoldings {
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
}
