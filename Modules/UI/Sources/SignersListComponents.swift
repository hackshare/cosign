import Foundation
import SwiftUI

struct PendingApprovalsOverview {
    let signerID: UUID
    let count: Int
    let signerLabels: [String]
}

struct PendingApprovalsBanner: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(CosignTheme.accent)
                    .frame(width: 10, height: 10)
                    .padding(8)
                    .background(CosignTheme.accentWash, in: .circle)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                CosignGlyphView(glyph: .chevronRight, size: 15, color: CosignTheme.inkDim)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CosignTheme.accentWash, in: .rect(cornerRadius: CosignTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                    .stroke(CosignTheme.accent.opacity(0.34), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: CosignTheme.Radius.card))
        }
        .buttonStyle(.plain)
    }
}

enum AddSignerSheet: Hashable, Identifiable {
    case hotWallet

    var id: Self {
        self
    }

    var title: String {
        CosignCopy.Signers.addSignerOptionTitle(for: self)
    }

    var subtitle: String {
        CosignCopy.Signers.addSignerOptionSubtitle(for: self)
    }

    var glyph: CosignGlyph {
        switch self {
        case .hotWallet:
            .key
        }
    }
}

private struct ComingSoonSignerRow: View {
    let title: String
    let subtitle: String
    let glyph: CosignGlyph

    var body: some View {
        HStack(spacing: 0) {
            CosignObjectRow(
                title: title,
                subtitle: subtitle,
                style: .plain,
                leading: {
                    CosignGlyphView(glyph: glyph, size: 18, color: CosignTheme.inkDim)
                        .frame(width: 36, height: 36)
                        .background(
                            CosignTheme.surface3,
                            in: .rect(cornerRadius: CosignTheme.Radius.medium)
                        )
                }
            )
            Text(CosignCopy.Signers.comingSoonTag)
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkFaint)
                .padding(.trailing, 14)
        }
        .opacity(0.6)
    }
}

struct AddSignerChooserSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (AddSignerSheet) -> Void

    var body: some View {
        CosignScreen {
            header

            CosignCard(padding: 0) {
                VStack(spacing: 0) {
                    Button {
                        onSelect(.hotWallet)
                    } label: {
                        CosignObjectRow(
                            title: AddSignerSheet.hotWallet.title,
                            subtitle: AddSignerSheet.hotWallet.subtitle,
                            style: .plain,
                            leading: {
                                CosignGlyphView(glyph: .key, size: 18, color: CosignTheme.accentDeep)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        CosignTheme.accentWash,
                                        in: .rect(cornerRadius: CosignTheme.Radius.medium)
                                    )
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("signer-option-hotWallet")

                    Divider()
                        .overlay(CosignTheme.line)
                        .padding(.leading, 14)

                    ComingSoonSignerRow(
                        title: CosignCopy.Signers.ledgerComingSoonTitle,
                        subtitle: CosignCopy.Signers.ledgerComingSoonSubtitle,
                        glyph: .shield
                    )

                    Divider()
                        .overlay(CosignTheme.line)
                        .padding(.leading, 14)

                    ComingSoonSignerRow(
                        title: CosignCopy.Signers.yubiKeyComingSoonTitle,
                        subtitle: CosignCopy.Signers.yubiKeyComingSoonSubtitle,
                        glyph: .wave
                    )
                }
            }
        }
        .cosignScreenIdentifier("screen.add-signer-chooser")
        .presentationDetents([.height(390), .medium])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(CosignTheme.inkGhost)
                .frame(width: 42, height: 4)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(CosignCopy.Signers.addSignerTitle)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.Signers.addSignerSubtitle)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.inkDim)
                }

                Spacer(minLength: 12)

                CosignGlyphButton(glyph: .xmark, accessibilityLabel: CosignCopy.Signers.closeAccessibilityLabel) {
                    dismiss()
                }
            }
        }
    }
}
