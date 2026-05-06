import SwiftUI

struct CosignCompactPageHeader<Accessory: View>: View {
    let title: String?
    let backAction: () -> Void
    let accessory: Accessory

    init(
        title: String? = nil,
        backAction: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.backAction = backAction
        self.accessory = accessory()
    }

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                Button(action: backAction) {
                    CosignGlyphView(glyph: .chevronLeft, size: 16, color: CosignTheme.inkDim)
                        .frame(width: 32, height: 32)
                        .background(CosignTheme.surface, in: .circle)
                        .overlay {
                            Circle().stroke(CosignTheme.line, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CosignCopy.Common.back)
                .accessibilityIdentifier("nav-back")

                Spacer(minLength: 12)

                accessory
            }

            if let title, !title.isEmpty {
                Text(title)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 44)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CosignPlainGlyphButton: View {
    let glyph: CosignGlyph
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CosignGlyphView(glyph: glyph, size: 16, color: CosignTheme.inkDim)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
