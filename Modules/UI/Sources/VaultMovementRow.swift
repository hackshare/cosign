import Indexer
import Squads
import SwiftUI

struct VaultMovementRow: View {
    let item: SquadActivityItem
    let vaultAddress: String
    var showsChevron = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(item.error == nil ? CosignTheme.ink : CosignTheme.riskRed)
                    .lineLimit(1)

                Text(subtitle)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                if let movementAmount {
                    Text(movementAmount.text)
                        .font(CosignTheme.FontStyle.mono)
                        .foregroundStyle(movementAmount.color)
                        .lineLimit(1)
                        .monospacedDigit()
                }

                Text(dateLabel)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
            }

            if showsChevron {
                CosignGlyphView(glyph: .chevronRight, size: 14, color: CosignTheme.inkGhost)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .contentShape(.rect(cornerRadius: CosignTheme.Radius.card))
    }

    private var title: String {
        if let counterparty {
            return counterparty
        }
        if let summary = item.action?.summary, !summary.isEmpty {
            return summary
        }
        return displayLabel(item.kind)
    }

    private var subtitle: String {
        var parts = [String]()
        if let action = item.action {
            parts.append(displayLabel(action.classification))
            if let program = action.effects.first?.program {
                parts.append(program)
            }
        } else {
            parts.append(displayLabel(item.kind))
        }
        return parts.joined(separator: " · ")
    }

    private var counterparty: String? {
        guard let effect = item.action?.effects.first else {
            return nil
        }
        if effect.source == vaultAddress, let destination = effect.destination {
            return cosignShortAddress(destination)
        }
        if effect.destination == vaultAddress, let source = effect.source {
            return cosignShortAddress(source)
        }
        return nil
    }

    private var movementAmount: (text: String, color: Color)? {
        guard let effect = item.action?.effects.first, let amount = formattedAmount(effect) else {
            return nil
        }
        if effect.source == vaultAddress {
            return ("-\(amount)", CosignTheme.riskRed)
        }
        if effect.destination == vaultAddress {
            return ("+\(amount)", CosignTheme.accentDeep)
        }
        return (amount, CosignTheme.inkDim)
    }

    private var dateLabel: String {
        guard item.timestampUnix > 0 else {
            return CosignCopy.Activity.unknownTimestamp
        }
        let date = Date(timeIntervalSince1970: TimeInterval(item.timestampUnix))
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func formattedAmount(_ effect: RelayInspectionEffect) -> String? {
        guard let amount = effect.amount, !amount.isEmpty else {
            return nil
        }
        let trimmed = amount
            .components(separatedBy: " to ")
            .first?
            .components(separatedBy: " from ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        if let asset = effect.asset, !trimmed.localizedCaseInsensitiveContains(asset) {
            return "\(trimmed) \(asset)"
        }
        return trimmed
    }
}
