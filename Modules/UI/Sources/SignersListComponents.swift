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
    case ledger
    case yubikey

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
        case .ledger:
            .shield
        case .yubikey:
            .wave
        }
    }
}

struct AddSignerChooserSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (AddSignerSheet) -> Void

    private let options: [AddSignerSheet] = [.hotWallet, .ledger, .yubikey]

    var body: some View {
        CosignScreen {
            header

            CosignCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        Button {
                            onSelect(option)
                        } label: {
                            CosignObjectRow(
                                title: option.title,
                                subtitle: option.subtitle,
                                style: .plain,
                                leading: {
                                    CosignGlyphView(glyph: option.glyph, size: 18, color: CosignTheme.accentDeep)
                                        .frame(width: 36, height: 36)
                                        .background(
                                            CosignTheme.accentWash,
                                            in: .rect(cornerRadius: CosignTheme.Radius.medium)
                                        )
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("signer-option-\(option)")

                        if index < options.count - 1 {
                            Divider()
                                .overlay(CosignTheme.line)
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .cosignScreenIdentifier("screen.add-signer-chooser")
        .presentationDetents([.height(330), .medium])
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
