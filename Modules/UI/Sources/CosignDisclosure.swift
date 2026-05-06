import SwiftUI

struct CosignDisclosure<Content: View>: View {
    let title: String
    var subtitle: String?
    var startsExpanded = false
    let content: Content

    @State private var isExpanded: Bool

    init(
        title: String,
        subtitle: String? = nil,
        startsExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.startsExpanded = startsExpanded
        self.content = content()
        _isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(CosignTheme.FontStyle.titleM)
                            .foregroundStyle(CosignTheme.ink)
                        if let subtitle {
                            Text(subtitle)
                                .font(CosignTheme.FontStyle.caption)
                                .foregroundStyle(CosignTheme.inkFaint)
                        }
                    }

                    Spacer(minLength: 8)

                    CosignGlyphView(glyph: .chevronRight, size: 15, color: CosignTheme.inkGhost)
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(CosignTheme.line)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                content
            }
        }
    }
}
