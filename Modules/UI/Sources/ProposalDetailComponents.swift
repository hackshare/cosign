import Indexer
import Squads
import SwiftUI

struct InstructionRow: View {
    let index: Int
    let instruction: DecodedInstructionDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(CosignCopy.ProposalDetail.instructionTitle(index: index))
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                Spacer()
                Text(displayLabel(instruction.kind))
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
            }

            Text(instruction.programLabel)
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkFaint)

            Text(instruction.summary)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.ink)

            if !uniqueAccounts.isEmpty {
                CosignDisclosure(
                    title: CosignCopy.ProposalDetail.accountsTitle,
                    subtitle: CosignCopy.ProposalDetail.rawAccountsSubtitle(count: uniqueAccounts.count)
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(uniqueAccounts, id: \.self) { account in
                            AddressRow(address: account)
                        }
                    }
                }
            }

            if !instruction.dataHex.isEmpty {
                CosignDisclosure(title: CosignCopy.ProposalDetail.rawDataTitle) {
                    Text(instruction.dataHex)
                        .font(CosignTheme.FontStyle.monoSmall)
                        .foregroundStyle(CosignTheme.inkFaint)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var uniqueAccounts: [String] {
        unique(instruction.accounts)
    }
}

struct AddressRow: View {
    let address: String

    var body: some View {
        CosignAddressText(address: address)
    }
}

func displayLabel(_ value: String) -> String {
    value
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
}

func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

extension SquadProposalDetail {
    var canOpenManualSimulation: Bool {
        switch status.lowercased() {
        case "draft", "active":
            true
        default:
            false
        }
    }

    var canRefreshRelaySimulation: Bool {
        switch status.lowercased() {
        case "approved", "executing":
            true
        default:
            false
        }
    }

    var isExecuted: Bool {
        status.lowercased() == "executed"
    }

    var isRejectedOrCancelled: Bool {
        ["rejected", "cancelled", "failed"].contains(status.lowercased())
    }

    var isTerminal: Bool {
        isExecuted || isRejectedOrCancelled
    }

    var canBeActedOn: Bool {
        switch status.lowercased() {
        case "active", "approved":
            true
        default:
            false
        }
    }
}

struct RelayInspectionActionView: View {
    let action: RelayInspectionAction?
    let fallbackLabel: String
    let fallbackColor: Color
    var context = ActionObjectContext.preSign

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let action {
                let actionObject = action.actionObject(context: context)
                ActionHeaderView(action: actionObject, size: .large)

                ForEach(action.warnings, id: \.code) { warning in
                    RiskBanner(warning: warning)
                }

                RolesCard(roles: actionObject.roles)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        CosignGlyphView(glyph: .search, size: 16, color: CosignTheme.ink)
                        Text(CosignCopy.ProposalDetail.actionLabel)
                            .font(CosignTheme.FontStyle.titleM)
                            .foregroundStyle(CosignTheme.ink)
                    }
                    Spacer()
                    InspectionBadge(label: badgeLabel, color: badgeColor)
                }
            }
        }
    }

    private var badgeLabel: String {
        guard let action, action.classification != "unknown" else {
            return fallbackLabel
        }
        return displayLabel(action.classification)
    }

    private var badgeColor: Color {
        guard let action else {
            return fallbackColor
        }
        return action.confidence.lowercased() == "low" ? CosignTheme.inkDim : CosignTheme.accentDeep
    }
}

struct InspectionBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(color.opacity(0.14), in: .rect(cornerRadius: CosignTheme.Radius.small))
    }
}

struct ProposalTerminalFooter: View {
    @Environment(\.openURL) private var openURL

    let explorerURL: URL?
    let rawURL: URL?
    let explorerIsPrimary: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let explorerURL {
                Button(CosignCopy.ProposalDetail.terminalOpenInExplorer) {
                    openURL(explorerURL)
                }
                .buttonStyle(CosignButtonStyle(
                    kind: explorerIsPrimary ? .primary : .secondary,
                    height: CosignButtonHeight.stacked
                ))
            }
            if let rawURL {
                Button(CosignCopy.ProposalDetail.terminalViewRaw) {
                    openURL(rawURL)
                }
                .buttonStyle(CosignButtonStyle(kind: .secondary, height: CosignButtonHeight.stacked))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(CosignTheme.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CosignTheme.line)
                .frame(height: 1)
        }
        .accessibilityIdentifier("proposal-terminal-footer")
    }
}

struct RiskBanner: View {
    let title: String
    let message: String
    let tone: CosignBannerTone

    init(title: String, message: String, tone: CosignBannerTone) {
        self.title = title
        self.message = message
        self.tone = tone
    }

    init(warning: RelayInspectionWarning) {
        self.init(
            title: cosignWarningTitle(warning),
            message: warning.message,
            tone: cosignWarningTone(for: warning.severity)
        )
    }

    var body: some View {
        CosignInlineBanner(tone: tone) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(tone.color)
                Text(message)
            }
        }
    }
}
