import SwiftUI

enum CosignEmptyStateKey {
    case emptyActivity
    case emptySignerActivity
    case emptyNFTs
    case emptyProposals
    case emptySquads
    case emptyTokens
    case emptyVaults
    case noSigners
    case noLocalSigner
    case noRelayInspection
    case rpcOnlyPricing

    var title: String {
        switch self {
        case .emptyActivity:
            CosignCopy.Empty.emptyActivityTitle
        case .emptySignerActivity:
            CosignCopy.Empty.emptySignerActivityTitle
        case .emptyNFTs:
            CosignCopy.Empty.emptyNFTsTitle
        case .emptyProposals:
            CosignCopy.Empty.emptyProposalsTitle
        case .emptySquads:
            CosignCopy.Empty.emptySquadsTitle
        case .emptyTokens:
            CosignCopy.Empty.emptyTokensTitle
        case .emptyVaults:
            CosignCopy.Empty.emptyVaultsTitle
        case .noSigners:
            CosignCopy.Empty.noSignersTitle
        case .noLocalSigner:
            CosignCopy.Empty.noLocalSignerTitle
        case .noRelayInspection:
            CosignCopy.Empty.noRelayInspectionTitle
        case .rpcOnlyPricing:
            CosignCopy.Pricing.unavailableTitle
        }
    }

    var message: String {
        switch self {
        case .emptyActivity:
            CosignCopy.Empty.emptyActivityMessage
        case .emptySignerActivity:
            CosignCopy.Empty.emptySignerActivityMessage
        case .emptyNFTs:
            CosignCopy.Empty.emptyNFTsMessage
        case .emptyProposals:
            CosignCopy.Empty.emptyProposalsMessage
        case .emptySquads:
            CosignCopy.Empty.emptySquadsMessage
        case .emptyTokens:
            CosignCopy.Empty.emptyTokensMessage
        case .emptyVaults:
            CosignCopy.Empty.emptyVaultsMessage
        case .noSigners:
            CosignCopy.Empty.noSignersMessage
        case .noLocalSigner:
            CosignCopy.Empty.noLocalSignerMessage
        case .noRelayInspection:
            CosignCopy.Empty.noRelayInspectionMessage
        case .rpcOnlyPricing:
            CosignCopy.Pricing.standardRPCMessage
        }
    }

    var glyph: CosignGlyph {
        switch self {
        case .emptyActivity, .emptySignerActivity:
            .wave
        case .emptyNFTs:
            .circle
        case .emptyProposals:
            .check
        case .emptySquads:
            .circle
        case .emptyTokens:
            .circle
        case .emptyVaults:
            .lock
        case .noSigners:
            .plus
        case .noLocalSigner:
            .plus
        case .noRelayInspection:
            .shield
        case .rpcOnlyPricing:
            .circle
        }
    }

    var tone: CosignEmptyStateTone {
        switch self {
        case .emptyProposals:
            .mint
        case .emptyVaults, .noLocalSigner, .noRelayInspection:
            .amber
        case .emptyActivity, .emptyNFTs, .emptySignerActivity, .emptySquads, .emptyTokens, .noSigners,
             .rpcOnlyPricing:
            .neutral
        }
    }

    var primaryActionTitle: String? {
        switch self {
        case .emptyProposals:
            CosignCopy.Empty.recentActivityAction
        case .emptySquads:
            CosignCopy.Empty.copyAddressAction
        case .emptyVaults:
            CosignCopy.Empty.viewMembersAction
        case .noSigners:
            CosignCopy.Empty.addSignerAction
        case .noLocalSigner:
            CosignCopy.Empty.addSignerAction
        case .rpcOnlyPricing:
            CosignCopy.Empty.configureRelayAction
        case .emptyActivity, .emptyNFTs, .emptySignerActivity, .emptyTokens,
             .noRelayInspection:
            nil
        }
    }

    var secondaryActionTitle: String? {
        nil
    }

    var primaryActionKind: CosignButtonKind {
        switch self {
        case .emptyProposals, .emptyVaults:
            .secondary
        case .emptyActivity, .emptyNFTs, .emptySignerActivity, .emptySquads, .emptyTokens, .noSigners,
             .noLocalSigner, .noRelayInspection, .rpcOnlyPricing:
            .primary
        }
    }

    var layout: CosignEmptyStateLayout {
        switch self {
        case .emptySquads, .emptyVaults, .noSigners:
            .fullPage
        case .emptyActivity, .emptyNFTs, .emptyProposals, .emptySignerActivity, .emptyTokens:
            .listReplacement
        case .noLocalSigner, .noRelayInspection, .rpcOnlyPricing:
            .card
        }
    }

    var borderStyle: StrokeStyle {
        switch self {
        case .emptyActivity, .emptyNFTs, .emptyProposals, .emptySignerActivity, .emptySquads, .emptyTokens,
             .emptyVaults,
             .noSigners:
            StrokeStyle(lineWidth: 1, dash: [5, 5])
        case .noLocalSigner, .noRelayInspection, .rpcOnlyPricing:
            StrokeStyle(lineWidth: 1)
        }
    }
}

enum CosignEmptyStateTone {
    case neutral
    case amber
    case mint
    case red

    var color: Color {
        switch self {
        case .neutral:
            CosignTheme.inkDim
        case .amber:
            CosignTheme.riskAmber
        case .mint:
            CosignTheme.mintDeep
        case .red:
            CosignTheme.riskRed
        }
    }

    var wash: Color {
        switch self {
        case .neutral:
            CosignTheme.surface2
        case .amber:
            CosignTheme.riskAmber.opacity(0.10)
        case .mint:
            CosignTheme.mintWash
        case .red:
            CosignTheme.riskRed.opacity(0.10)
        }
    }
}

enum CosignEmptyStateLayout {
    case card
    case listReplacement
    case fullPage

    var minHeight: CGFloat? {
        switch self {
        case .card:
            nil
        case .listReplacement:
            148
        case .fullPage:
            210
        }
    }
}

struct CosignEmptyState: View {
    let title: String
    let glyph: CosignGlyph
    var message: String?
    var primaryActionTitle: String?
    var secondaryActionTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryAction: (() -> Void)?
    var primaryActionKind: CosignButtonKind
    var primaryActionIdentifier: String?
    var tone: CosignEmptyStateTone
    var layout: CosignEmptyStateLayout
    var borderStyle: StrokeStyle

    init(
        title: String,
        systemImage: String,
        message: String? = nil,
        primaryActionTitle: String? = nil,
        secondaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil,
        primaryActionKind: CosignButtonKind = .primary,
        tone: CosignEmptyStateTone = .neutral,
        layout: CosignEmptyStateLayout = .card,
        borderStyle: StrokeStyle = StrokeStyle(lineWidth: 1)
    ) {
        self.title = title
        glyph = CosignGlyph(systemName: systemImage) ?? .document
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.primaryActionKind = primaryActionKind
        self.tone = tone
        self.layout = layout
        self.borderStyle = borderStyle
    }

    init(
        key: CosignEmptyStateKey,
        primaryActionTitle: String? = nil,
        primaryActionIdentifier: String? = nil,
        secondaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        title = key.title
        glyph = key.glyph
        message = key.message
        self.primaryActionTitle = primaryActionTitle ?? key.primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle ?? key.secondaryActionTitle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        primaryActionKind = key.primaryActionKind
        self.primaryActionIdentifier = primaryActionIdentifier
        tone = key.tone
        layout = key.layout
        borderStyle = key.borderStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CosignGlyphView(
                glyph: glyph,
                size: 22,
                color: tone.color
            )
            .frame(width: 40, height: 40)
            .background(tone.wash, in: .rect(cornerRadius: CosignTheme.Radius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                    .stroke(borderColor, lineWidth: 1)
            }
            Text(title)
                .font(CosignTheme.FontStyle.titleL)
                .foregroundStyle(CosignTheme.ink)
                .multilineTextAlignment(.leading)
            if let message {
                Text(message)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if visiblePrimaryActionTitle != nil || visibleSecondaryActionTitle != nil {
                HStack(spacing: 8) {
                    if let primaryActionTitle = visiblePrimaryActionTitle {
                        Button(primaryActionTitle) {
                            primaryAction?()
                        }
                        .buttonStyle(CosignButtonStyle(kind: primaryActionKind, fillsWidth: false))
                        .accessibilityIdentifier(primaryActionIdentifier ?? "")
                    }
                    if let secondaryActionTitle = visibleSecondaryActionTitle {
                        Button(secondaryActionTitle) {
                            secondaryAction?()
                        }
                        .buttonStyle(CosignButtonStyle(kind: .tertiary, fillsWidth: false))
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: layout.minHeight, alignment: .leading)
        .padding(22)
        .background(CosignTheme.surface, in: .rect(cornerRadius: CosignTheme.Radius.hero))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.hero)
                .stroke(borderColor, style: borderStyle)
        }
        .contentShape(.rect(cornerRadius: CosignTheme.Radius.hero))
    }

    private var borderColor: Color {
        switch tone {
        case .amber, .mint, .red:
            tone.color.opacity(0.35)
        case .neutral:
            CosignTheme.lineStrong
        }
    }

    private var visiblePrimaryActionTitle: String? {
        primaryAction == nil ? nil : primaryActionTitle
    }

    private var visibleSecondaryActionTitle: String? {
        secondaryAction == nil ? nil : secondaryActionTitle
    }
}
