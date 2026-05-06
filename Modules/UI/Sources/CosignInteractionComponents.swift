import SwiftUI

struct CosignSkeletonBar: View {
    let width: CGFloat?
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(CosignTheme.surface3)
            .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                CosignTheme.surface3,
                                CosignTheme.surface2,
                                CosignTheme.surface3
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(0.55)
            }
    }
}

enum CosignButtonKind {
    case primary
    case accent
    case secondary
    case tertiary
    case destructive

    func colors(isEnabled: Bool) -> CosignButtonColors {
        guard isEnabled else {
            return CosignButtonColors(
                background: CosignTheme.surface3,
                foreground: CosignTheme.inkFaint,
                border: CosignTheme.line
            )
        }

        switch self {
        case .primary:
            return CosignButtonColors(background: CosignTheme.ink, foreground: CosignTheme.background)
        case .accent:
            return CosignButtonColors(background: CosignTheme.accent, foreground: CosignTheme.accentInk)
        case .secondary:
            return CosignButtonColors(
                background: CosignTheme.surface2,
                foreground: CosignTheme.ink,
                border: CosignTheme.line
            )
        case .tertiary:
            return CosignButtonColors(
                background: Color.clear,
                foreground: CosignTheme.inkDim,
                border: CosignTheme.line
            )
        case .destructive:
            return CosignButtonColors(
                background: CosignTheme.surface,
                foreground: CosignTheme.riskRed,
                border: CosignTheme.riskRed.opacity(0.40)
            )
        }
    }
}

struct CosignButtonColors {
    let background: Color
    let foreground: Color
    var border: Color?
}

enum CosignButtonHeight {
    /// Single primary CTA.
    static let primary: CGFloat = 52
    /// Buttons in a multi-action cluster (primary + More).
    static let stacked: CGFloat = 48
}

struct CosignButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let kind: CosignButtonKind
    var fillsWidth = true
    var isLoading = false
    var height: CGFloat = CosignButtonHeight.primary

    func makeBody(configuration: Configuration) -> some View {
        let colors = kind.colors(isEnabled: isEnabled)

        configuration.label
            .font(CosignTheme.FontStyle.body)
            .foregroundStyle(colors.foreground)
            .opacity(isLoading ? 0 : 1)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: height)
            .padding(.horizontal, 14)
            .background(colors.background, in: .rect(cornerRadius: CosignTheme.Radius.control))
            .overlay {
                if let border = colors.border {
                    RoundedRectangle(cornerRadius: CosignTheme.Radius.control)
                        .stroke(border, lineWidth: 1)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(colors.foreground)
                }
            }
            .opacity(configuration.isPressed ? 0.74 : 1)
    }
}

enum CosignBannerTone {
    case neutral
    case amber
    case red
    case mint

    var color: Color {
        switch self {
        case .neutral:
            CosignTheme.inkFaint
        case .amber:
            CosignTheme.riskAmber
        case .red:
            CosignTheme.riskRed
        case .mint:
            CosignTheme.accentDeep
        }
    }
}

struct CosignInlineBanner<Content: View>: View {
    let tone: CosignBannerTone
    let content: Content

    init(tone: CosignBannerTone = .neutral, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(tone.color)
                .frame(width: 3)
                .clipShape(.capsule)
            content
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                .stroke(CosignTheme.line, lineWidth: 1)
        }
    }
}

struct CosignSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            CosignGlyphView(glyph: .search, size: 17, color: CosignTheme.inkFaint)
            TextField(placeholder, text: $text)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    CosignGlyphView(glyph: .xmark, size: 13, color: CosignTheme.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CosignCopy.Common.clearSearchAccessibilityLabel)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(CosignTheme.surface, in: .rect(cornerRadius: CosignTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                .stroke(CosignTheme.line, lineWidth: 1)
        }
    }
}

struct CosignFlowHeader: View {
    let title: String
    var subtitle: String?
    var cancelTitle = CosignCopy.Common.cancel
    var showsCancel = true
    var isCancelDisabled = false
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if showsCancel {
                    HStack {
                        Button(cancelTitle) {
                            onCancel()
                        }
                        .buttonStyle(CosignButtonStyle(kind: .secondary, fillsWidth: false))
                        .disabled(isCancelDisabled)
                        Spacer()
                    }
                }

                VStack(spacing: 2) {
                    Text(title)
                        .font(CosignTheme.FontStyle.titleL)
                        .foregroundStyle(CosignTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkDim)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, showsCancel ? 82 : 0)
            }
        }
        .padding(.bottom, 4)
    }
}
