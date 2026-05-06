import Squads
import SwiftUI

extension SquadDetailView {
    func squadAssetCard(_ detail: SquadDetail) -> some View {
        let summary = assetSummary(for: detail)

        return CosignCard(radius: CosignTheme.Radius.hero, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(CosignCopy.SquadDetail.combinedBalance.uppercased())
                        .font(CosignTheme.FontStyle.eyebrow)
                        .foregroundStyle(CosignTheme.inkFaint)

                    Text(nativeBalanceText(summary, vaultCount: detail.vaults.count))
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(CosignTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .monospacedDigit()

                    if let demoEstimatedUSD = demoEstimatedUSDText(for: summary) {
                        Text(demoEstimatedUSD)
                            .font(CosignTheme.FontStyle.monoSmall)
                            .foregroundStyle(CosignTheme.inkFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    CosignMetricPill(title: CosignCopy.SquadDetail.tokensMetric, value: "\(summary.tokenCount)")
                    CosignMetricPill(title: CosignCopy.SquadDetail.nftsMetric, value: "\(summary.nftCount)")
                    CosignMetricPill(title: CosignCopy.SquadDetail.vaultsMetric, value: "\(detail.vaults.count)")
                }
            }
        }
    }

    func squadMetadataCard(_ detail: SquadDetail) -> some View {
        CosignCard {
            HStack(spacing: 8) {
                CosignMetricPill(
                    title: CosignCopy.SquadDetail.latestTransactionMetric,
                    value: CosignCopy.SquadDetail.latestTransaction(index: detail.transactionIndex)
                )
                CosignMetricPill(
                    title: CosignCopy.SquadDetail.staleTransactionMetric,
                    value: staleTransactionText(detail.staleTransactionIndex)
                )
                CosignMetricPill(
                    title: CosignCopy.SquadDetail.timelockMetric,
                    value: timeLockText(detail.timeLockSeconds)
                )
            }
        }
    }
}
