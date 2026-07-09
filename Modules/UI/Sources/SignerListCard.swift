import CosignCore
import Persistence
import SwiftUI

struct SignerListMembershipSummary: Equatable {
    let squadCount: Int?
    let openProposalCount: Int
    let didFail: Bool
}

struct SignerListCard: View {
    let signer: RegisteredSigner
    let membershipSummary: SignerListMembershipSummary?

    var body: some View {
        let pubkey = CosignCore.base58(signer.pubkey)

        HStack(alignment: .center, spacing: 12) {
            signerAvatar

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(signer.label)
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)

                    Spacer(minLength: 8)

                    if let squadCount = membershipSummary?.squadCount {
                        Text(CosignCopy.Signers.squadCountSubtitle(count: squadCount))
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkFaint)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 7) {
                    addressLabel(pubkey)
                    metadataDot
                    statusLabel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CosignGlyphView(glyph: .chevronRight, size: 15, color: CosignTheme.inkGhost)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(CosignTheme.surface, in: .rect(cornerRadius: CosignTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                .stroke(CosignTheme.line, lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: CosignTheme.Radius.card))
        .contextMenu {
            Button {
                copyToPasteboard(pubkey)
            } label: {
                HStack(spacing: 8) {
                    CosignGlyphView(glyph: .copy, size: 14)
                    Text(CosignCopy.Signers.copySignerAddress)
                }
            }
        }
    }

    private func addressLabel(_ address: String) -> some View {
        Text(shortAddress(address))
            .font(CosignTheme.FontStyle.monoSmall)
            .foregroundStyle(CosignTheme.inkFaint)
            .lineLimit(1)
    }

    private var metadataDot: some View {
        Circle()
            .fill(CosignTheme.inkGhost)
            .frame(width: 3, height: 3)
    }

    private var statusLabel: some View {
        Text(statusLine)
            .font(CosignTheme.FontStyle.caption)
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .layoutPriority(1)
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 12 else {
            return address
        }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }

    private var statusLine: String {
        guard let membershipSummary else {
            return CosignCopy.Signers.loadingMembershipStatus
        }
        if membershipSummary.didFail {
            return CosignCopy.Signers.unableToLoadMembershipStatus
        }
        if membershipSummary.openProposalCount > 0 {
            return CosignCopy.Signers.pendingApprovalsStatus(count: membershipSummary.openProposalCount)
        }
        return CosignCopy.Signers.allClear
    }

    private var statusColor: Color {
        guard let membershipSummary else {
            return CosignTheme.inkFaint
        }
        if membershipSummary.didFail {
            return CosignTheme.riskRed
        }
        if membershipSummary.openProposalCount > 0 {
            return CosignTheme.accentDeep
        }
        return CosignTheme.inkFaint
    }

    private var signerAvatar: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(avatarGradient)
            .frame(width: 44, height: 44)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.28))
                    .frame(width: 28, height: 28)
                    .offset(x: -7, y: -7)
            }
    }

    private var avatarGradient: LinearGradient {
        if signer.label == CosignCopy.Demo.operationsSignerLabel {
            return LinearGradient(
                colors: [Color(hex: 0x7CF2B0), Color(hex: 0x0F2018)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if signer.label == CosignCopy.Demo.treasurySignerLabel {
            return LinearGradient(
                colors: [CosignTheme.accent, Color(hex: 0x241808)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if signer.label == CosignCopy.Demo.localDevnetSignerLabel {
            return LinearGradient(
                colors: [Color(hex: 0x8AA8FF), Color(hex: 0x0B142B)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        switch signer.type {
        case .hotWallet:
            return LinearGradient(
                colors: [CosignTheme.accent, Color(hex: 0x241808)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
