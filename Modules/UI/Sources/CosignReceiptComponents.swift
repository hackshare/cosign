import SwiftUI

struct CosignSuccessReceipt: View {
    let title: String
    let message: String
    var addressTitle: String?
    var address: String?
    var copyAccessibilityLabel = "Copy Address"

    var body: some View {
        CosignCard(radius: CosignTheme.Radius.hero, padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                CosignGlyphView(glyph: .check, size: 30, color: CosignTheme.mint)
                    .frame(width: 68, height: 68)
                    .background(CosignTheme.mintWash, in: .circle)
                    .overlay {
                        Circle().stroke(CosignTheme.mint.opacity(0.40), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                    Text(message)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let addressTitle, let address {
                    Divider()
                        .overlay(CosignTheme.line)
                    CosignAddressBlock(
                        title: addressTitle,
                        address: address,
                        accessibilityLabel: copyAccessibilityLabel
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CosignReceiptActionChip: View {
    let title: String
    let glyph: CosignGlyph
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CosignReceiptActionChipLabel(title: title, glyph: glyph)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "receipt-action-\(title.lowercased())")
    }
}

struct CosignReceiptActionChipLabel: View {
    let title: String
    let glyph: CosignGlyph

    var body: some View {
        HStack(spacing: 7) {
            CosignGlyphView(glyph: glyph, size: 14, color: CosignTheme.inkDim)
            Text(title)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                .stroke(CosignTheme.line, lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: CosignTheme.Radius.medium))
    }
}

struct CosignReceiptActionGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            content
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }
}

struct CosignReceiptDoneFooter: View {
    var onViewProposal: (() -> Void)?
    let onDone: () -> Void

    var body: some View {
        CosignStickyFooter {
            HStack(spacing: 10) {
                if let onViewProposal {
                    Button(CosignCopy.ProposalReceipt.viewProposal, action: onViewProposal)
                        .buttonStyle(CosignButtonStyle(kind: .secondary, height: CosignButtonHeight.stacked))
                }
                Button(CosignCopy.Common.done, action: onDone)
                    .buttonStyle(CosignButtonStyle(
                        kind: .primary,
                        height: onViewProposal == nil ? CosignButtonHeight.primary : CosignButtonHeight.stacked
                    ))
            }
        }
    }
}

struct ReceiptSummaryHeader: View {
    let summary: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(summary)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(CosignCopy.ProposalReceipt.confirmedBadge)
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.mint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CosignTheme.mintWash, in: .capsule)
            }
            .padding(.horizontal, CosignFactLayout.horizontalPadding)
            .padding(.vertical, CosignFactLayout.verticalPadding)

            Divider()
                .overlay(CosignTheme.line)
                .padding(.leading, CosignFactLayout.horizontalPadding)
        }
    }
}
