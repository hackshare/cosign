import SwiftUI

struct ActionHeaderView: View {
    let action: ActionObject
    var size: ActionHeaderSize = .medium

    var body: some View {
        VStack(alignment: .leading, spacing: size == .large ? 14 : 8) {
            HStack(spacing: 6) {
                SeverityPill(severity: action.severity)
                ConfidencePill(confidence: action.confidence, source: action.source)
            }

            Text(action.title)
                .font(size == .large ? .system(size: 26, weight: .medium, design: .rounded) : CosignTheme.FontStyle
                    .titleM)
                .foregroundStyle(CosignTheme.ink)
                .lineLimit(size == .large ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = action.subtitle {
                Text(subtitle)
                    .font(size == .large ? CosignTheme.FontStyle.body : CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkDim)
            }
        }
    }
}

enum ActionHeaderSize {
    case medium
    case large
}

struct SeverityPill: View {
    let severity: ActionSeverity

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(severity.color)
                .frame(width: 5, height: 5)
            Text(severity.label)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(severity.color)
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .background(severity.color.opacity(0.10), in: .capsule)
        .overlay {
            Capsule().stroke(severity.color.opacity(0.22), lineWidth: 1)
        }
    }
}

struct ConfidencePill: View {
    let confidence: ActionConfidence
    let source: String?

    var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0 ..< 4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < confidence.filledBars ? barColor : CosignTheme.inkGhost)
                        .frame(width: 3, height: CGFloat(5 + index * 2))
                }
            }
            Text(confidence.label)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
            if let source {
                Text(CosignCopy.ProposalDetail.confidenceSourceSubtitle(source: source))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(barColor)
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .background(CosignTheme.surface2, in: .capsule)
        .overlay {
            Capsule().stroke(CosignTheme.line, lineWidth: 1)
        }
    }

    private var barColor: Color {
        switch confidence {
        case .partial, .unknown:
            CosignTheme.riskAmber
        case .known, .idl:
            CosignTheme.inkDim
        }
    }
}

struct RolesCard: View {
    let roles: [ActionRole]

    var body: some View {
        CosignCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(roles.enumerated()), id: \.element.id) { index, role in
                    RoleRow(role: role, isLast: index == roles.count - 1)
                }
            }
        }
    }
}

struct RoleRow: View {
    let role: ActionRole
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if shouldStack {
                    verticalLayout
                } else {
                    ViewThatFits(in: .horizontal) {
                        horizontalLayout
                        verticalLayout
                    }
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, CosignFactLayout.horizontalPadding)

            if !isLast {
                Divider()
                    .overlay(CosignTheme.line)
                    .padding(.leading, dividerLeadingPadding)
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: CosignFactLayout.columnSpacing) {
            CosignFactLabel(role.label, lineLimit: labelLineLimit)
                .frame(width: CosignFactLayout.labelWidth, alignment: .leading)
                .padding(.top, 2)
                .layoutPriority(3)
            valueLayout
                .layoutPriority(2)
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            CosignFactLabel(role.label)
            valueLayout
        }
    }

    private var valueLayout: some View {
        VStack(alignment: .leading, spacing: 3) {
            if role.isAddressLike {
                CosignAddressText(
                    address: role.value,
                    displayAddress: cosignShortAddress(role.value),
                    size: 13,
                    color: role.isDanger ? CosignTheme.riskRed : CosignTheme.ink
                )
            } else {
                Text(role.value)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(role.isDanger ? CosignTheme.riskRed : CosignTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let subvalue = role.subvalue {
                Text(subvalue)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shouldStack: Bool {
        layoutRule != .fixed
    }

    private var layoutRule: CosignFactLayout.Rule {
        CosignFactLayout.rule(
            label: role.label,
            value: role.subvalue.map { "\(role.value) \($0)" } ?? role.value,
            isAddressLike: role.isAddressLike
        )
    }

    private var labelLineLimit: Int {
        1
    }

    private var dividerLeadingPadding: CGFloat {
        shouldStack ? CosignFactLayout.horizontalPadding :
            CosignFactLayout.horizontalPadding + CosignFactLayout.labelWidth + CosignFactLayout.columnSpacing
    }
}
