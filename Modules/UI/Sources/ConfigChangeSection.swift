import Squads
import SwiftUI

struct ConfigChangeSection: View {
    let rows: [ConfigChangeRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(CosignCopy.ProposalDetail.configAuthorityBadge)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CosignTheme.riskAmber)
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(
                        CosignTheme.riskAmber.opacity(0.14),
                        in: .rect(cornerRadius: CosignTheme.Radius.small)
                    )
                Spacer(minLength: 0)
            }

            CosignInlineBanner(tone: .amber) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(CosignCopy.ProposalDetail.authorityBannerTitle)
                        .font(CosignTheme.FontStyle.caption.weight(.semibold))
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.ProposalDetail.authorityBannerBody)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }
            }

            CosignSectionTitle(
                title: CosignCopy.ProposalDetail.configChangesSectionTitle,
                trailing: CosignCopy.ProposalDetail.configChangesCount(rows.count)
            )
            CosignCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        ConfigChangeRowView(row: row)
                        if index < rows.count - 1 {
                            Divider().overlay(CosignTheme.line).padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }
}

private struct ConfigChangeRowView: View {
    let row: ConfigChangeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CosignTheme.inkFaint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13).padding(.horizontal, 14)
        .background(rowWash)
    }

    /// A faint amber wash marks a loosening of signing control; everything else is unwashed.
    private var rowWash: Color {
        if case let .signingPower(_, oldOf, newOf) = row, newOf > oldOf {
            return CosignTheme.riskAmber.opacity(0.06)
        }
        return .clear
    }

    private var label: String {
        switch row {
        case .permission: CosignCopy.ProposalDetail.configPermissionLabel
        case .add: CosignCopy.ProposalDetail.configAddLabel
        case .remove: CosignCopy.ProposalDetail.configRemoveLabel
        case .threshold: CosignCopy.ProposalDetail.configThresholdLabel
        case .signingPower: CosignCopy.ProposalDetail.configSigningPowerLabel
        case .timeLock: CosignCopy.ProposalDetail.configTimeLockLabel
        case .rentCollector: CosignCopy.ProposalDetail.configRentCollectorLabel
        }
    }

    @ViewBuilder private var content: some View {
        switch row {
        case let .permission(address, old, new):
            HStack(spacing: 6) {
                Text(cosignShortAddress(address))
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.ink)
                Text(perms(old))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .strikethrough()
                Text("\u{2192}")
                    .foregroundStyle(CosignTheme.inkFaint)
                Text(perms(new))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.mint)
            }
        case let .add(address, permissions):
            HStack(spacing: 6) {
                Text(cosignShortAddress(address))
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.ProposalDetail.configNewChip)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(CosignTheme.mint)
                    .padding(.vertical, 2).padding(.horizontal, 6)
                    .background(CosignTheme.mint.opacity(0.12), in: .capsule)
                Text(perms(permissions))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.mint)
            }
        case let .remove(address):
            HStack(spacing: 6) {
                Text(cosignShortAddress(address))
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .strikethrough()
                Text(CosignCopy.ProposalDetail.configRemovedNote)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.riskAmber)
            }
        case let .threshold(oldValue, oldOf, newValue, newOf):
            Text(
                CosignCopy.ProposalDetail.thresholdDiff(
                    oldValue: oldValue,
                    oldOf: oldOf,
                    newValue: newValue,
                    newOf: newOf
                )
            )
            .font(CosignTheme.FontStyle.mono)
            .foregroundStyle(CosignTheme.ink)
        case let .signingPower(threshold, oldOf, newOf):
            signingPowerContent(threshold: threshold, oldOf: oldOf, newOf: newOf)
        case let .timeLock(oldSeconds, newSeconds):
            Text("\(cosignTimeLockDisplay(seconds: oldSeconds)) \u{2192} \(cosignTimeLockDisplay(seconds: newSeconds))")
                .font(CosignTheme.FontStyle.mono)
                .foregroundStyle(CosignTheme.ink)
        case let .rentCollector(old, new):
            let oldLabel = old.map { cosignShortAddress($0) } ?? CosignCopy.ProposalDetail.configRentCollectorNone
            let newLabel = new.map { cosignShortAddress($0) } ?? CosignCopy.ProposalDetail.configRentCollectorNone
            Text("\(oldLabel) \u{2192} \(newLabel)")
                .font(CosignTheme.FontStyle.mono)
                .foregroundStyle(CosignTheme.ink)
        }
    }

    @ViewBuilder
    private func signingPowerContent(threshold: Int, oldOf: Int, newOf: Int) -> some View {
        let looser = newOf > oldOf
        let accent = looser ? CosignTheme.riskAmber : CosignTheme.inkDim
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(CosignCopy.ProposalDetail.configApprovalRatio)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.ink)
                Text(signingPowerChip(looser: looser, unanimous: newOf == threshold))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.vertical, 2).padding(.horizontal, 6)
                    .background(accent.opacity(0.12), in: .capsule)
                Text(CosignCopy.ProposalDetail.configDerivedTag)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(CosignTheme.inkFaint)
                    .padding(.vertical, 2).padding(.horizontal, 5)
                    .background(CosignTheme.inkFaint.opacity(0.10), in: .capsule)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text("\(threshold) of \(oldOf)")
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .strikethrough()
                Text("\u{2192}").foregroundStyle(CosignTheme.inkFaint)
                Text("\(threshold) of \(newOf)")
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(accent)
            }
            Text(CosignCopy.ProposalDetail.signingPowerCaveat(signatures: threshold, looser: looser))
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signingPowerChip(looser: Bool, unanimous: Bool) -> String {
        if looser { return CosignCopy.ProposalDetail.configLooserChip }
        return unanimous
            ? CosignCopy.ProposalDetail.configNowUnanimousChip
            : CosignCopy.ProposalDetail.configTighterChip
    }

    private func perms(_ memberPerms: MemberPermissions) -> String {
        var parts: [String] = []
        if memberPerms.canInitiate { parts.append(CosignCopy.ManageSquad.permissionPropose) }
        if memberPerms.canVote { parts.append(CosignCopy.ManageSquad.permissionVote) }
        if memberPerms.canExecute { parts.append(CosignCopy.ManageSquad.permissionExecute) }
        return parts.isEmpty
            ? CosignCopy.ProposalDetail.configPermissionsNone
            : parts.joined(separator: " \u{00B7} ")
    }
}
