import Foundation
import Squads
import SwiftUI

struct SignerHomeSquadListRow: View {
    let row: SignerHomeSquadRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.summary.displayName ?? signerHomeShortAddress(row.summary.address))
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if row.openProposalCount > 0 {
                Text(pendingLabel)
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(pendingColor)
                    .monospacedDigit()
            }

            CosignGlyphView(glyph: .chevronRight, size: 14, color: CosignTheme.inkGhost)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: CosignTheme.Radius.card))
    }

    private var subtitle: String {
        CosignCopy.Signers.squadSubtitle(
            threshold: row.summary.threshold,
            members: row.summary.memberCount,
            transactionIndex: row.summary.transactionIndex
        )
    }

    private var pendingLabel: String {
        "\(row.openProposalCount)"
    }

    private var pendingColor: Color {
        row.openProposalCount > 0 ? CosignTheme.accentDeep : CosignTheme.inkFaint
    }
}

struct SignerHomeRecentActivityRow: View {
    let item: SquadActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(statusLabel)
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(statusColor)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(statusColor.opacity(0.10), in: .rect(cornerRadius: CosignTheme.Radius.small))

                Text(title)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(relativeTimestamp)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
            }

            if let subtitle {
                Text(subtitle)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: CosignTheme.Radius.card))
    }

    private var title: String {
        item.action?.summary ?? displayKind(item.kind)
    }

    private var subtitle: String? {
        var parts = [String]()
        if let actionSubtitle = item.action?.actionObject.subtitle {
            parts.append(actionSubtitle)
        } else if item.action != nil {
            parts.append(displayKind(item.kind))
        }
        parts.append(CosignCopy.Activity.slot(item.slot))
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private enum ActivityStatus {
        case approved, executed, failed
    }

    private var activityStatus: ActivityStatus {
        if item.error != nil { return .failed }
        if item.kind == "approve" { return .approved }
        return .executed
    }

    private var statusLabel: String {
        switch activityStatus {
        case .approved: CosignCopy.SignerHome.approvedStatus
        case .executed: CosignCopy.Activity.executedStatus
        case .failed: CosignCopy.Activity.failedStatus
        }
    }

    private var statusColor: Color {
        switch activityStatus {
        case .approved: CosignTheme.mint
        case .executed: CosignTheme.inkFaint
        case .failed: CosignTheme.riskRed
        }
    }

    private var relativeTimestamp: String {
        guard item.timestampUnix > 0 else {
            return CosignCopy.Activity.unknownTimestamp
        }
        let date = Date(timeIntervalSince1970: TimeInterval(item.timestampUnix))
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private func signerHomeShortAddress(_ address: String) -> String {
    guard address.count > 12 else {
        return address
    }
    return "\(address.prefix(4))...\(address.suffix(4))"
}

private func displayKind(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
}
