import SwiftUI

struct CosignAddressBlock: View {
    let title: String
    let address: String
    let accessibilityLabel: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(CosignTheme.FontStyle.eyebrow)
                .foregroundStyle(CosignTheme.inkFaint)

            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    CosignAddressText(address: address, size: 13, color: CosignTheme.ink, copyOnTap: false)
                        .opacity(copied ? 0 : 1)
                    if copied {
                        CosignCopiedValueFeedback(value: address)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    copyToPasteboard(address)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(1600))
                        await MainActor.run {
                            copied = false
                        }
                    }
                } label: {
                    CosignGlyphView(glyph: .copy, size: 15, color: CosignTheme.inkDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
            }
        }
    }
}

struct CosignNavigationRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                CosignGlyphView(
                    glyph: CosignGlyph(systemName: systemImage) ?? .document,
                    size: 17,
                    color: CosignTheme.accentDeep
                )
                .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }
            }

            Spacer(minLength: 8)
            accessory
            CosignGlyphView(glyph: .chevronRight, size: 15, color: CosignTheme.inkGhost)
        }
    }
}

struct CosignMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(CosignTheme.inkFaint)
            Text(value)
                .font(CosignTheme.FontStyle.monoSmall)
                .foregroundStyle(CosignTheme.ink)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.small))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.small)
                .stroke(CosignTheme.line, lineWidth: 1)
        }
    }
}

struct CosignStatusBadge: View {
    let status: String

    var body: some View {
        Text(displayLabel(status))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(color.opacity(0.14), in: .rect(cornerRadius: CosignTheme.Radius.small))
    }

    private var color: Color {
        switch status.lowercased() {
        case "active", "approved", "executing":
            CosignTheme.accentDeep
        case "executed", "confirmed", "finalized", "succeeded":
            CosignTheme.mint
        case "rejected", "cancelled", "failed":
            CosignTheme.riskRed
        default:
            CosignTheme.inkFaint
        }
    }
}

enum CosignTabsStyle {
    case pill
    case underline
}

struct CosignSegmentedTabs<T: Hashable>: View {
    let tabs: [T]
    @Binding var selection: T
    var style: CosignTabsStyle = .pill
    let title: (T) -> String

    var body: some View {
        switch style {
        case .pill:
            HStack(spacing: 2) {
                ForEach(tabs, id: \.self) { tab in
                    tabButton(tab)
                        .padding(.vertical, 9)
                        .background(
                            selection == tab ? CosignTheme.surface : Color.clear,
                            in: .capsule
                        )
                        .shadow(color: .black.opacity(selection == tab ? 0.25 : 0), radius: 4, y: 1)
                }
            }
            .padding(4)
            .background(CosignTheme.surface3, in: .capsule)
        case .underline:
            HStack(spacing: 18) {
                ForEach(tabs, id: \.self) { tab in
                    VStack(spacing: 8) {
                        tabButton(tab)
                        Capsule()
                            .fill(selection == tab ? CosignTheme.ink : Color.clear)
                            .frame(height: 2)
                    }
                }
            }
            .padding(.bottom, 2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(CosignTheme.line)
                    .frame(height: 1)
            }
        }
    }

    private func tabButton(_ tab: T) -> some View {
        Button {
            selection = tab
        } label: {
            Text(title(tab))
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(selection == tab ? CosignTheme.ink : CosignTheme.inkFaint)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tabAccessibilityIdentifier(for: tab))
    }

    private func tabAccessibilityIdentifier(for tab: T) -> String {
        let normalizedTitle = title(tab)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        return "tab-\(normalizedTitle)"
    }
}

struct CosignLoadingCard: View {
    var body: some View {
        CosignCard {
            VStack(alignment: .leading, spacing: 12) {
                CosignSkeletonBar(width: 78, height: 18, cornerRadius: 9)
                CosignSkeletonBar(width: nil, height: 16)
                CosignSkeletonBar(width: 180, height: 12)
            }
            .padding(.vertical, 10)
        }
    }
}

struct CosignNetworkFooter: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(CosignTheme.accent)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(CosignTheme.inkFaint)
                .tracking(0.2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

struct CosignStepProgress: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1 ... max(totalSteps, 1), id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? CosignTheme.accent : CosignTheme.surface3)
                    .frame(height: 4)
            }
        }
    }
}

struct CosignStickyFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CosignTheme.line)
            content
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
        }
        .background(CosignTheme.background.ignoresSafeArea(edges: .bottom))
    }
}
