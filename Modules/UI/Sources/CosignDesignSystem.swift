import SwiftUI

enum CosignTheme {
    // Surfaces — dark-first; elevation reads by tint, darkest is the canvas.
    static let background = Color(hex: 0x08090B)
    static let surface = Color(hex: 0x0F1114)
    static let surface2 = Color(hex: 0x15181C)
    static let surface3 = Color(hex: 0x1B1F24)

    // Ink — primary text plus the secondary/tertiary/ghost opacity ramp.
    static let ink = Color(hex: 0xF4F5F3)
    static let inkDim = ink.opacity(0.62)
    static let inkFaint = ink.opacity(0.36)
    static let inkGhost = ink.opacity(0.18)

    // Borders — white-based hairlines on the dark canvas.
    static let line = Color.white.opacity(0.07)
    static let lineStrong = Color.white.opacity(0.12)

    // Accent — single amber accent for CTAs, progress, and brand.
    static let accent = Color(hex: 0xF2C26C)
    static let accentDeep = Color(hex: 0xD69A3B)
    static let accentWash = accent.opacity(0.10)
    static let selectedWash = accent.opacity(0.12)
    static let accentInk = Color(hex: 0x1A1305)

    // Status & risk — theme-independent, reserved for meaning.
    static let mint = Color(hex: 0x7CF2B0)
    static let mintDeep = Color(hex: 0x7CF2B0)
    static let mintWash = mint.opacity(0.10)
    static let riskAmber = Color(hex: 0xF2A65C)
    static let riskRed = Color(hex: 0xF26464)

    /// Letter-spacing for uppercase eyebrow / tag / badge labels.
    enum Tracking {
        static let label: CGFloat = 0.2
        static let tag: CGFloat = 0.6
        static let badge: CGFloat = 0.8
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let control: CGFloat = 14
        static let card: CGFloat = 16
        static let hero: CGFloat = 18
    }

    enum FontStyle {
        static let displayL = Font.system(size: 34, weight: .semibold, design: .rounded)
        static let display = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let titleL = Font.system(size: 22, weight: .medium, design: .rounded)
        static let titleM = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 14, weight: .medium, design: .rounded)
        static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
        static let eyebrow = Font.system(size: 11, weight: .medium, design: .rounded)
        static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    }
}

enum CosignLayout {
    static let screenBottomPadding: CGFloat = 28
    static let stickyFooterContentClearance: CGFloat = 32
    static let estimatedStickyFooterHeight: CGFloat = 104
    static let estimatedSheetStickyFooterHeight: CGFloat = 156

    static func screenBottomPadding(stickyFooterHeight: CGFloat) -> CGFloat {
        max(screenBottomPadding, stickyFooterHeight + stickyFooterContentClearance)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension View {
    func cosignPage() -> some View {
        background(CosignTheme.background.ignoresSafeArea())
            .tint(CosignTheme.accentDeep)
    }

    func cosignCard(
        radius: CGFloat = CosignTheme.Radius.card,
        padding: CGFloat = 16
    ) -> some View {
        self
            .padding(padding)
            .background(CosignTheme.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(CosignTheme.line, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: radius))
    }

    func cosignPrimaryAction() -> some View {
        font(CosignTheme.FontStyle.body)
            .foregroundStyle(CosignTheme.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CosignTheme.accent, in: .rect(cornerRadius: CosignTheme.Radius.control))
    }

    func cosignSecondaryAction() -> some View {
        font(CosignTheme.FontStyle.body)
            .foregroundStyle(CosignTheme.inkDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.control)
                    .stroke(CosignTheme.line, lineWidth: 1)
            }
    }

    func cosignField() -> some View {
        font(CosignTheme.FontStyle.body)
            .foregroundStyle(CosignTheme.ink)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.control)
                    .stroke(CosignTheme.line, lineWidth: 1)
            }
    }
}

struct CosignScreen<Content: View>: View {
    var bottomPadding = CosignLayout.screenBottomPadding
    @ViewBuilder let content: Content

    init(
        bottomPadding: CGFloat = CosignLayout.screenBottomPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.bottomPadding = bottomPadding
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cosignPage()
    }
}

struct CosignAnchoredFooterScreen<Content: View, Footer: View>: View {
    var bottomPadding = CosignLayout.screenBottomPadding
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        bottomPadding: CGFloat = CosignLayout.screenBottomPadding,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.bottomPadding = bottomPadding
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                    Spacer(minLength: 0)
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
            }
            .cosignPage()
        }
    }
}

extension View {
    func cosignScreenIdentifier(_ identifier: String) -> some View {
        overlay(alignment: .topLeading) {
            Text("")
                .frame(width: 1, height: 1)
                .accessibilityLabel(identifier)
                .accessibilityIdentifier(identifier)
        }
    }

    func cosignMeasureHeight(_ height: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: CosignMeasuredHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(CosignMeasuredHeightPreferenceKey.self) { newHeight in
            guard newHeight > 0, abs(height.wrappedValue - newHeight) > 0.5 else {
                return
            }
            height.wrappedValue = newHeight
        }
    }
}

private struct CosignMeasuredHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CosignCard<Content: View>: View {
    var radius = CosignTheme.Radius.card
    var padding: CGFloat = 16
    let content: Content

    init(
        radius: CGFloat = CosignTheme.Radius.card,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .cosignCard(radius: radius, padding: padding)
    }
}

struct CosignSectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(CosignTheme.FontStyle.eyebrow)
                .foregroundStyle(CosignTheme.inkFaint)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
            }
        }
    }
}

struct CosignWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            CosignMark(size: 24)
            Text(CosignCopy.Common.appName)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(CosignTheme.ink)
    }
}

struct CosignMark: View {
    var size: CGFloat = 24
    var color = CosignTheme.ink
    var dot = CosignTheme.accent

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            var mark = Path()
            mark.addArc(
                center: CGPoint(x: 12 * scale, y: 12 * scale),
                radius: 8.5 * scale,
                startAngle: .degrees(38),
                endAngle: .degrees(322),
                clockwise: false
            )
            context.stroke(
                mark,
                with: .color(color),
                style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round)
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: (18.4 - 2.4) * scale,
                    y: (12 - 2.4) * scale,
                    width: 4.8 * scale,
                    height: 4.8 * scale
                )),
                with: .color(dot)
            )
        }
        .frame(width: size, height: size)
    }
}

struct CosignIconButton: View {
    let glyph: CosignGlyph
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CosignGlyphView(glyph: glyph, size: 16, color: CosignTheme.inkDim)
                .frame(width: 36, height: 36)
                .background(CosignTheme.surface, in: .circle)
                .overlay {
                    Circle().stroke(CosignTheme.line, lineWidth: 1)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
