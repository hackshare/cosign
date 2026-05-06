import SwiftUI

enum CosignObjectRowStyle {
    case card
    case plain
}

struct CosignObjectRow: View {
    let title: String
    var subtitle: String?
    var metadata: String?
    var copyValue: String?
    var copyAccessibilityLabel = CosignCopy.Common.copy
    var style: CosignObjectRowStyle = .card
    var showsChevron = true

    private let leading: AnyView
    private let badges: AnyView
    private let accessory: AnyView
    private let footer: AnyView
    @State private var copied = false

    init(
        title: String,
        subtitle: String? = nil,
        metadata: String? = nil,
        copyValue: String? = nil,
        copyAccessibilityLabel: String = CosignCopy.Common.copy,
        style: CosignObjectRowStyle = .card,
        showsChevron: Bool = true,
        @ViewBuilder leading: () -> some View = { EmptyView() },
        @ViewBuilder badges: () -> some View = { EmptyView() },
        @ViewBuilder accessory: () -> some View = { EmptyView() },
        @ViewBuilder footer: () -> some View = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.copyValue = copyValue
        self.copyAccessibilityLabel = copyAccessibilityLabel
        self.style = style
        self.showsChevron = showsChevron
        self.leading = AnyView(leading())
        self.badges = AnyView(badges())
        self.accessory = AnyView(accessory())
        self.footer = AnyView(footer())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                leading

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(CosignTheme.FontStyle.titleM)
                            .foregroundStyle(CosignTheme.ink)
                            .lineLimit(1)
                        badges
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkFaint)
                            .lineLimit(1)
                    }

                    if let metadata {
                        CosignObjectMetadataLine(
                            value: metadata,
                            copyValue: copyValue,
                            accessibilityLabel: copyAccessibilityLabel,
                            copied: copied
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                accessory

                if showsChevron {
                    CosignGlyphView(glyph: .chevronRight, size: 15, color: CosignTheme.inkGhost)
                }
            }

            footer
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .modifier(CosignObjectRowContainer(style: style))
        .contentShape(.rect(cornerRadius: CosignTheme.Radius.card))
        .contextMenu {
            if let copyValue {
                Button {
                    copyToPasteboard(copyValue)
                    markCopied()
                } label: {
                    HStack(spacing: 8) {
                        CosignGlyphView(glyph: .copy, size: 14)
                        Text(copyAccessibilityLabel)
                    }
                }
            }
        }
    }

    private func markCopied() {
        copied = true
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            await MainActor.run {
                copied = false
            }
        }
    }
}

struct CosignObjectRowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Content) {
        self.action = action
        content = label
    }

    var body: some View {
        Button(action: action) {
            rowContent
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: CosignTheme.Radius.card))
    }
}

struct CosignObjectNavigationLink<Value: Hashable, Content: View>: View {
    let value: Value
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationLink(value: value) {
            rowContent
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: CosignTheme.Radius.card))
    }
}

private struct CosignObjectRowContainer: ViewModifier {
    let style: CosignObjectRowStyle

    func body(content: Content) -> some View {
        switch style {
        case .card:
            content
                .background(CosignTheme.surface, in: .rect(cornerRadius: CosignTheme.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                        .stroke(CosignTheme.line, lineWidth: 1)
                }
        case .plain:
            content
        }
    }
}

private struct CosignObjectMetadataLine: View {
    let value: String
    let copyValue: String?
    let accessibilityLabel: String
    let copied: Bool

    var body: some View {
        valueText
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(copyValue == nil ? value :
                CosignCopy.Common.copyAvailableAccessibility(value: value, action: accessibilityLabel))
    }

    private var valueText: some View {
        ZStack(alignment: .leading) {
            rawValueText
                .opacity(copied ? 0 : 1)
            if copied {
                CosignCopiedValueFeedback(value: copyValue ?? value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private var rawValueText: some View {
        HStack(spacing: 8) {
            Text(value)
                .font(CosignTheme.FontStyle.monoSmall)
                .foregroundStyle(CosignTheme.inkFaint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
