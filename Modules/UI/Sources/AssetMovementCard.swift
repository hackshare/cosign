import Indexer
import SwiftUI

struct AssetMovementCard: View {
    enum Variant {
        case predicted
        case executed
        case attempted

        var sectionTitle: String {
            switch self {
            case .predicted: CosignCopy.Movement.sectionPredicted
            case .executed: CosignCopy.Movement.sectionExecuted
            case .attempted: CosignCopy.Movement.sectionAttempted
            }
        }
    }

    let movement: AssetMovement
    let variant: Variant

    var body: some View {
        if !movement.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: variant.sectionTitle)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(movement.legs.enumerated()), id: \.offset) { index, leg in
                            if index > 0 {
                                Divider().overlay(CosignTheme.line).padding(.leading, 14)
                            }
                            legRow(leg)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    private func legRow(_ leg: AssetMovementLeg) -> some View {
        let isOutflow = leg.direction == .outflow
        let tone = isOutflow ? CosignTheme.riskRed : CosignTheme.mint
        let sign = isOutflow ? "-" : "+"
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(sign)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(tone)
                // The relay's amount is a display string that already carries the
                // unit (e.g. "250 SOL"), matching the decoded-fields "Amount" row.
                Text(leg.amount)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(tone)
                    .monospacedDigit()
            }
            if let counterparty = leg.counterparty {
                Text(isOutflow
                    ? CosignCopy.Movement.leg(destination: cosignMediumAddress(counterparty))
                    : CosignCopy.Movement.leg(source: cosignMediumAddress(counterparty)))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkDim)
            }
        }
    }
}
