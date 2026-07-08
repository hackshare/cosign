import Squads
import SwiftUI

extension ManageSquadConfigView {
    // MARK: - Existing member row (original members from current on-chain state)

    func existingMemberRow(_ member: SquadMember, index: Int, detail: SquadDetail) -> some View {
        let isRemoved = removedKeys.contains(member.pubkey)
        let desired = desiredMembers.first(where: { $0.pubkey == member.pubkey })
        let isChanged = desired.map { des in
            des.canInitiate != member.canInitiate
                || des.canVote != member.canVote
                || des.canExecute != member.canExecute
        } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            existingMemberHeader(member, index: index, isRemoved: isRemoved, isChanged: isChanged)
            if !isRemoved, let desired {
                permissionToggleRow(desired: desired, detail: detail)
            }
        }
    }

    private func existingMemberHeader(
        _ member: SquadMember, index: Int, isRemoved: Bool, isChanged: Bool
    ) -> some View {
        let isYou = currentSignerAddresses.contains(member.pubkey)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cosignShortAddress(member.pubkey))
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(isRemoved ? CosignTheme.inkFaint : CosignTheme.ink)
                        .strikethrough(isRemoved, color: CosignTheme.accentDeep)
                    if !isRemoved {
                        if isYou {
                            memberBadge(
                                CosignCopy.ManageSquad.youBadge,
                                foreground: CosignTheme.accentDeep,
                                background: CosignTheme.accentWash
                            )
                        }
                        if isChanged {
                            memberBadge(
                                CosignCopy.ManageSquad.changedBadge,
                                foreground: CosignTheme.mint,
                                background: CosignTheme.mintWash
                            )
                        }
                    }
                }
                Text(cosignShortAddress(member.pubkey, prefix: 6, suffix: 6))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkDim)
            }
            Spacer()
            Button {
                toggleMemberRemoval(member.pubkey, original: member)
            } label: {
                CosignGlyphView(
                    glyph: .xmark,
                    size: 14,
                    color: isRemoved ? CosignTheme.accentDeep : CosignTheme.inkDim
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(isYou ? "manage-squad-remove-you" : "manage-squad-remove-\(index)")
        }
    }

    // MARK: - Added member row (new members not in current on-chain state)

    func addedMemberRow(_ member: SquadMember, newIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(cosignShortAddress(member.pubkey))
                            .font(CosignTheme.FontStyle.titleM)
                            .foregroundStyle(CosignTheme.mint)
                        memberBadge(
                            CosignCopy.ManageSquad.addedBadge,
                            foreground: CosignTheme.mint,
                            background: CosignTheme.mintWash
                        )
                    }
                    Text(cosignShortAddress(member.pubkey, prefix: 6, suffix: 6))
                        .font(CosignTheme.FontStyle.monoSmall)
                        .foregroundStyle(CosignTheme.inkDim)
                }
                Spacer()
                Button {
                    removeAddedMember(member.pubkey)
                } label: {
                    CosignGlyphView(glyph: .xmark, size: 14, color: CosignTheme.inkDim)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("manage-squad-remove-added-\(newIndex)")
            }
            permissionToggleRowNew(member: member)
        }
    }

    // MARK: - Permission toggle row (existing member — shows changed state)

    private func permissionToggleRow(desired: SquadMember, detail: SquadDetail) -> some View {
        let current = detail.members.first(where: { $0.pubkey == desired.pubkey })
        let proposeChanged = current.map { $0.canInitiate != desired.canInitiate } ?? false
        let voteChanged = current.map { $0.canVote != desired.canVote } ?? false
        let executeChanged = current.map { $0.canExecute != desired.canExecute } ?? false
        guard let idx = desiredMembers.firstIndex(where: { $0.pubkey == desired.pubkey }) else {
            return AnyView(EmptyView())
        }
        return AnyView(HStack(spacing: 8) {
            permissionChip(
                label: CosignCopy.ManageSquad.permissionPropose,
                granted: desired.canInitiate,
                changed: proposeChanged,
                accessibilityID: "manage-squad-perm-\(idx)-propose"
            ) {
                flipPermission(at: idx, propose: true)
            }
            permissionChip(
                label: CosignCopy.ManageSquad.permissionVote,
                granted: desired.canVote,
                changed: voteChanged,
                accessibilityID: "manage-squad-perm-\(idx)-vote"
            ) {
                flipPermission(at: idx, vote: true)
            }
            permissionChip(
                label: CosignCopy.ManageSquad.permissionExecute,
                granted: desired.canExecute,
                changed: executeChanged,
                accessibilityID: "manage-squad-perm-\(idx)-execute"
            ) {
                flipPermission(at: idx, execute: true)
            }
        })
    }

    // MARK: - Permission toggle row (new member — no changed state)

    private func permissionToggleRowNew(member: SquadMember) -> some View {
        guard let idx = desiredMembers.firstIndex(where: { $0.pubkey == member.pubkey }) else {
            return AnyView(EmptyView())
        }
        return AnyView(HStack(spacing: 8) {
            permissionChip(
                label: CosignCopy.ManageSquad.permissionPropose,
                granted: member.canInitiate,
                changed: false,
                accessibilityID: "manage-squad-perm-\(idx)-propose"
            ) {
                flipPermission(at: idx, propose: true)
            }
            permissionChip(
                label: CosignCopy.ManageSquad.permissionVote,
                granted: member.canVote,
                changed: false,
                accessibilityID: "manage-squad-perm-\(idx)-vote"
            ) {
                flipPermission(at: idx, vote: true)
            }
            permissionChip(
                label: CosignCopy.ManageSquad.permissionExecute,
                granted: member.canExecute,
                changed: false,
                accessibilityID: "manage-squad-perm-\(idx)-execute"
            ) {
                flipPermission(at: idx, execute: true)
            }
        })
    }

    // MARK: - Permission chip

    private func permissionChip(
        label: String,
        granted: Bool,
        changed: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if granted {
                    Circle()
                        .fill(CosignTheme.accentInk)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .stroke(CosignTheme.inkFaint, lineWidth: 1.5)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .lineLimit(1)
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(granted ? CosignTheme.accentInk : CosignTheme.inkFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(height: 30)
            .background(granted ? CosignTheme.accent : CosignTheme.surface2, in: .capsule)
            .overlay {
                if changed {
                    Capsule()
                        .stroke(CosignTheme.mint, lineWidth: 1.5)
                }
            }
        }
        .frame(minHeight: 44)
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }

    // MARK: - Badge helper

    func memberBadge(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(CosignTheme.FontStyle.eyebrow)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: .capsule)
    }
}
