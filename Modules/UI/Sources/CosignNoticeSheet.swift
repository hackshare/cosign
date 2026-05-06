import SwiftUI

struct CosignNoticeSheet: View {
    let title: String
    let message: String
    var tone: CosignBannerTone = .neutral
    var buttonTitle = CosignCopy.Common.done
    let onDismiss: () -> Void

    var body: some View {
        CosignScreen {
            header

            CosignCard(radius: CosignTheme.Radius.hero, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    CosignGlyphView(glyph: glyph, size: 28, color: tone.color)
                        .frame(width: 62, height: 62)
                        .background(tone.color.opacity(0.10), in: .circle)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(CosignTheme.FontStyle.display)
                            .foregroundStyle(CosignTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(message)
                            .font(CosignTheme.FontStyle.body)
                            .foregroundStyle(CosignTheme.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(buttonTitle) {
                onDismiss()
            }
            .buttonStyle(CosignButtonStyle(kind: .primary))
        }
        .presentationDetents([.height(360), .medium])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Spacer()
            CosignGlyphButton(glyph: .xmark, accessibilityLabel: CosignCopy.Common.dismiss) {
                onDismiss()
            }
        }
    }

    private var glyph: CosignGlyph {
        switch tone {
        case .red, .amber:
            .warning
        case .mint:
            .check
        case .neutral:
            .document
        }
    }
}

public struct CosignPromptSheet: View {
    private let title: String
    private let message: String
    private let primaryButtonTitle: String
    private let secondaryButtonTitle: String?
    private let onPrimary: () -> Void
    private let onSecondary: (() -> Void)?

    public init(
        title: String,
        message: String,
        primaryButtonTitle: String,
        secondaryButtonTitle: String? = nil,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    public var body: some View {
        CosignScreen {
            header

            CosignCard(radius: CosignTheme.Radius.hero, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    CosignGlyphView(glyph: .document, size: 28, color: CosignTheme.accentDeep)
                        .frame(width: 62, height: 62)
                        .background(CosignTheme.accentWash, in: .circle)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(CosignTheme.FontStyle.display)
                            .foregroundStyle(CosignTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(message)
                            .font(CosignTheme.FontStyle.body)
                            .foregroundStyle(CosignTheme.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 10) {
                Button(primaryButtonTitle) {
                    onPrimary()
                }
                .buttonStyle(CosignButtonStyle(kind: .primary))

                if let secondaryButtonTitle {
                    Button(secondaryButtonTitle) {
                        onSecondary?()
                    }
                    .buttonStyle(CosignButtonStyle(kind: .secondary))
                }
            }
        }
        .presentationDetents([.height(470), .medium])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Spacer()
            if onSecondary != nil {
                CosignGlyphButton(glyph: .xmark, accessibilityLabel: CosignCopy.Common.dismiss) {
                    onSecondary?()
                }
            }
        }
    }
}
