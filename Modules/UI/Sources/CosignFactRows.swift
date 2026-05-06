import SwiftUI

struct CosignKeyValueRow: View {
    let label: String
    let value: String
    var detail: String?
    var isAddressLike = false
    var isLast = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch layoutRule {
                case .fixed:
                    adaptiveHorizontalLayout(labelLineLimit: 1)
                case .wrapLabel:
                    verticalLayout
                case .stacked:
                    verticalLayout
                }
            }
            .padding(.vertical, CosignFactLayout.verticalPadding)
            .padding(.horizontal, CosignFactLayout.horizontalPadding)

            if !isLast {
                Divider()
                    .overlay(CosignTheme.line)
                    .padding(.leading, dividerLeadingPadding)
            }
        }
    }

    private func horizontalLayout(labelLineLimit: Int) -> some View {
        HStack(alignment: .top, spacing: CosignFactLayout.columnSpacing) {
            CosignFactLabel(label, lineLimit: labelLineLimit)
                .frame(width: CosignFactLayout.labelWidth, alignment: .leading)
                .padding(.top, 2)
                .layoutPriority(3)
            valueView(alignment: .leading)
                .layoutPriority(2)
        }
    }

    private func adaptiveHorizontalLayout(labelLineLimit: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout(labelLineLimit: labelLineLimit)
            verticalLayout
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            CosignFactLabel(label)
            valueView(alignment: .leading)
        }
    }

    private var layoutRule: CosignFactLayout.Rule {
        CosignFactLayout.rule(
            label: label,
            value: detail.map { "\(value) \($0)" } ?? value,
            isAddressLike: isAddressLike
        )
    }

    private var dividerLeadingPadding: CGFloat {
        switch layoutRule {
        case .wrapLabel, .stacked:
            CosignFactLayout.horizontalPadding
        case .fixed:
            CosignFactLayout.horizontalPadding + CosignFactLayout.labelWidth + CosignFactLayout.columnSpacing
        }
    }

    private func valueView(alignment: Alignment) -> some View {
        VStack(alignment: horizontalAlignment(for: alignment), spacing: 3) {
            if isAddressLike {
                CosignAddressText(
                    address: value,
                    displayAddress: cosignShortAddress(value),
                    size: 12,
                    color: CosignTheme.ink
                )
                .frame(maxWidth: .infinity, alignment: alignment)
            } else {
                Text(value)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.ink)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let detail {
                Text(detail)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func horizontalAlignment(for alignment: Alignment) -> HorizontalAlignment {
        switch alignment {
        case .trailing:
            .trailing
        case .center:
            .center
        default:
            .leading
        }
    }
}

enum CosignFactLayout {
    enum Rule: Equatable {
        case fixed
        case wrapLabel
        case stacked
    }

    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12
    static let labelWidth: CGFloat = 108
    static let columnSpacing: CGFloat = 12

    static func rule(label: String, value: String, isAddressLike: Bool) -> Rule {
        if label.count > 16 || value.count > (isAddressLike ? 38 : 58) {
            return .stacked
        }
        if label.count > 12 {
            return .wrapLabel
        }
        return .fixed
    }
}

struct CosignFactLabel: View {
    let text: String
    let lineLimit: Int

    init(_ text: String, lineLimit: Int = 1) {
        self.text = text
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(CosignTheme.inkFaint)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .truncationMode(.tail)
    }
}
