import Squads
import SwiftUI

extension SquadDetailView {
    @ViewBuilder
    func pricingNotice(for detail: SquadDetail) -> some View {
        if demoMode == nil, prices == nil, assetSummary(for: detail).hasPriceableHoldings {
            CosignPricingNotice()
        }
    }
}
