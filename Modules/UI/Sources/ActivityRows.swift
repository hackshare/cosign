import Indexer
import Squads
import SwiftUI

struct ActivityNavigationRow: View {
    let item: SquadActivityItem
    let explorerURL: URL?
    let canInspect: Bool
    let ownVaultAccounts: Set<String>

    var body: some View {
        if canInspect {
            CosignObjectNavigationLink(value: Route.transactionInspection(signature: item.signature)) {
                ActivityRow(item: item, explorerURL: nil, showsInspectionHint: true, ownVaultAccounts: ownVaultAccounts)
            }
        } else {
            ActivityRow(item: item, explorerURL: explorerURL, ownVaultAccounts: ownVaultAccounts)
        }
    }
}

struct ActivityRow: View {
    let item: SquadActivityItem
    let explorerURL: URL?
    var showsInspectionHint = false
    let ownVaultAccounts: Set<String>

    var body: some View {
        CosignObjectRow(
            title: rowTitle,
            subtitle: rowSubtitle,
            metadata: item.signature,
            style: .plain,
            showsChevron: showsInspectionHint,
            badges: {
                Text(CosignCopy.Activity.slot(item.slot))
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .monospacedDigit()
                if item.error != nil {
                    failedPill
                }
                riskBadge
            },
            footer: {
                footerContent
            }
        )
    }

    private var activityTitle: String {
        if let action = item.action, action.classification != "unknown" {
            return displayLabel(action.classification)
        }
        return displayKind(item.kind)
    }

    private var rowTitle: String {
        item.action?.summary ?? activityTitle
    }

    private var movementOneLiner: String? {
        guard !ownVaultAccounts.isEmpty,
              let effects = item.action?.effects, !effects.isEmpty
        else {
            return nil
        }
        let movement = AssetMovement.build(from: effects, ownAccounts: ownVaultAccounts)
        guard let leg = movement.primaryLeg else { return nil }
        if let counterparty = leg.counterparty {
            let short = cosignShortAddress(counterparty, prefix: 6, suffix: 6)
            return leg.direction == .outflow
                ? CosignCopy.Movement.leg(destination: short)
                : CosignCopy.Movement.leg(source: short)
        }
        return leg.direction == .outflow ? CosignCopy.Movement.toLabel : CosignCopy.Movement.fromLabel
    }

    private var rowSubtitle: String? {
        var parts = [String]()
        if let oneLiner = movementOneLiner {
            parts.append(oneLiner)
        } else if let actionSubtitle = item.action?.actionObject.subtitle {
            parts.append(actionSubtitle)
        } else if item.action != nil {
            parts.append(displayKind(item.kind))
        }
        if item.timestampUnix > 0 {
            parts.append(activityDate(item.timestampUnix))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var failedPill: some View {
        Text(CosignCopy.Activity.failedStatus)
            .font(CosignTheme.FontStyle.caption)
            .foregroundStyle(CosignTheme.riskRed)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(CosignTheme.riskRed.opacity(0.12), in: .capsule)
    }

    @ViewBuilder
    private var riskBadge: some View {
        if let action = item.action, !action.warnings.isEmpty {
            CosignGlyphView(glyph: .warning, size: 11, color: CosignTheme.riskRed)
                .padding(.vertical, 2)
                .padding(.horizontal, 5)
                .background(CosignTheme.riskRed.opacity(0.12), in: .capsule)
        } else if let action = item.action {
            let confidence = action.actionObject.confidence
            if confidence == .unknown || confidence == .partial {
                ConfidencePill(confidence: confidence, source: nil)
            }
        }
    }

    @ViewBuilder
    private var footerContent: some View {
        if let error = item.error {
            HStack(spacing: 6) {
                CosignGlyphView(glyph: .warning, size: 13, color: CosignTheme.riskRed)
                Text(error)
            }
            .font(CosignTheme.FontStyle.caption)
            .foregroundStyle(CosignTheme.riskRed)
        }

        if let explorerURL {
            Link(destination: explorerURL) {
                HStack(spacing: 6) {
                    CosignGlyphView(glyph: .external, size: 13, color: CosignTheme.accentDeep)
                    Text(CosignCopy.Activity.openInExplorer)
                }
            }
            .font(CosignTheme.FontStyle.caption)
        } else if showsInspectionHint {
            HStack(spacing: 6) {
                CosignGlyphView(glyph: .search, size: 13, color: CosignTheme.inkDim)
                Text(CosignCopy.Activity.inspectTransaction)
            }
            .font(CosignTheme.FontStyle.caption)
            .foregroundStyle(CosignTheme.inkDim)
        }
    }
}

private func displayKind(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
}

private func activityDate(_ timestampUnix: Int64) -> String {
    Date(timeIntervalSince1970: TimeInterval(timestampUnix)).formatted(date: .abbreviated, time: .shortened)
}
