import Indexer
import Squads
import SwiftUI

struct ProposalDecisionHeader: View {
    let action: ActionObject
    let proposal: SquadProposalDetail
    let squadAddress: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            badgeLine

            Text(displayTitle)
                .font(CosignTheme.FontStyle.display)
                .foregroundStyle(CosignTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if hasFlowLine {
                flowLine
            } else if let subtitle = action.subtitle {
                Text(subtitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsUnknownWarning {
                CosignInlineBanner(tone: .amber) {
                    Text(CosignCopy.ProposalDetail.unknownActionWarning)
                }
            } else {
                ForEach(action.warnings, id: \.code) { warning in
                    ActionWarningBanner(warning: warning)
                }
            }
        }
        .padding(.top, 2)
    }

    private var badgeLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                SeverityPill(severity: action.severity)
                ConfidencePill(confidence: action.confidence, source: action.source)
                Spacer(minLength: 6)
                CosignStatusBadge(status: proposal.status)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    SeverityPill(severity: action.severity)
                    ConfidencePill(confidence: action.confidence, source: action.source)
                }
                CosignStatusBadge(status: proposal.status)
            }
        }
    }

    @ViewBuilder
    private var flowLine: some View {
        if let flowEndpoints {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(CosignCopy.ProposalDetail.fromLabel)
                    .foregroundStyle(CosignTheme.inkDim)
                Text(cosignShortAddress(flowEndpoints.source))
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.ProposalDetail.toLabel)
                    .foregroundStyle(CosignTheme.inkDim)
                Text(cosignShortAddress(flowEndpoints.destination))
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(destinationIsRisky ? CosignTheme.riskRed : CosignTheme.ink)
            }
            .font(CosignTheme.FontStyle.body)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hasFlowLine: Bool {
        flowEndpoints != nil
    }

    private var displayTitle: String {
        guard
            hasFlowLine,
            action.title.lowercased().hasPrefix("transfer "),
            let amount = roleValue(CosignCopy.ActionObject.amountRole)
        else {
            return action.title
        }

        return CosignCopy.ProposalDetail.sendTitle(amount: amount)
    }

    private var showsUnknownWarning: Bool {
        action.warnings.isEmpty && action.confidence == .unknown
    }

    private var flowEndpoints: (source: String, destination: String)? {
        guard
            let source = roleValue(CosignCopy.ActionObject.fromRole),
            let destination = roleValue(CosignCopy.ActionObject.toRole)
        else {
            return nil
        }
        return (source, destination)
    }

    private var destinationIsRisky: Bool {
        action.roles.contains { role in
            role.label.caseInsensitiveCompare("To") == .orderedSame && role.isDanger
        }
    }

    private func roleValue(_ label: String) -> String? {
        action.roles.first { role in
            role.label.caseInsensitiveCompare(label) == .orderedSame
        }?.value
    }
}

struct DecodedInstructionSummaryRow: View {
    let index: Int
    let instruction: DecodedInstructionDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CosignCopy.ProposalDetail.instructionTitle(index: index))
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)

                Spacer(minLength: 8)

                Text(displayLabel(instruction.kind))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(kindColor)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(kindColor.opacity(0.10), in: .capsule)
            }

            Text(instruction.programLabel)
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkFaint)
                .lineLimit(1)

            Text(instruction.summary)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
    }

    private var kindColor: Color {
        instruction.kind.lowercased() == "raw" ? CosignTheme.riskAmber : CosignTheme.accentDeep
    }
}

struct VoteProgressRing: View {
    let approvals: UInt32
    let threshold: UInt16

    var body: some View {
        ZStack {
            Circle()
                .stroke(CosignTheme.surface3, lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    CosignTheme.accentDeep,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(String(approvals))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.ProposalDetail.voteRingThreshold(threshold))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
            }
            .monospacedDigit()
        }
        .frame(width: 58, height: 58)
    }

    private var progress: CGFloat {
        guard threshold > 0 else {
            return 0
        }
        return min(CGFloat(approvals) / CGFloat(threshold), 1)
    }
}

struct VoteCountPill: View {
    let glyph: CosignGlyph
    let title: String
    let value: UInt32

    var body: some View {
        HStack(spacing: 5) {
            CosignGlyphView(glyph: glyph, size: 12, color: CosignTheme.inkFaint)
            Text(String(value))
                .monospacedDigit()
            Text(title)
        }
        .font(CosignTheme.FontStyle.caption)
        .foregroundStyle(CosignTheme.inkFaint)
        .padding(.vertical, 4)
        .padding(.horizontal, 7)
        .background(CosignTheme.surface2, in: .capsule)
    }
}

struct ProposalVoterChipCloud: View {
    let members: [SquadMember]
    let proposal: SquadProposalDetail

    private let columns = [
        GridItem(.adaptive(minimum: 106), spacing: 7, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(members) { member in
                ProposalVoterChip(
                    address: member.pubkey,
                    state: voteState(for: member.pubkey)
                )
            }
        }
    }

    private func voteState(for address: String) -> ProposalVoterState {
        if proposal.votersYes.contains(address) {
            return .approved
        }
        if proposal.votersNo.contains(address) {
            return .rejected
        }
        if proposal.votersCancelled.contains(address) {
            return .cancelled
        }
        return .pending
    }
}

private struct ProposalVoterChip: View {
    let address: String
    let state: ProposalVoterState

    var body: some View {
        HStack(spacing: 5) {
            CosignGlyphView(glyph: state.glyph, size: 10, color: state.foreground)
            Text(cosignShortAddress(address, prefix: 4, suffix: 4))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .font(CosignTheme.FontStyle.monoSmall)
        .foregroundStyle(state.foreground)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(state.background, in: .capsule)
        .overlay {
            Capsule().stroke(state.stroke, lineWidth: 1)
        }
    }
}

private enum ProposalVoterState {
    case approved
    case rejected
    case cancelled
    case pending

    var glyph: CosignGlyph {
        switch self {
        case .approved:
            .check
        case .rejected, .cancelled:
            .xmark
        case .pending:
            .circle
        }
    }

    var foreground: Color {
        switch self {
        case .approved:
            CosignTheme.accentDeep
        case .rejected, .cancelled:
            CosignTheme.riskRed
        case .pending:
            CosignTheme.inkFaint
        }
    }

    var background: Color {
        switch self {
        case .approved:
            CosignTheme.accent.opacity(0.12)
        case .rejected, .cancelled:
            CosignTheme.riskRed.opacity(0.08)
        case .pending:
            CosignTheme.surface2
        }
    }

    var stroke: Color {
        switch self {
        case .approved:
            CosignTheme.accent.opacity(0.28)
        case .rejected, .cancelled:
            CosignTheme.riskRed.opacity(0.18)
        case .pending:
            CosignTheme.line
        }
    }
}

struct ActionWarningBanner: View {
    let warning: RelayInspectionWarning

    var body: some View {
        CosignInlineBanner(tone: tone) {
            VStack(alignment: .leading, spacing: 3) {
                Text(cosignWarningTitle(warning))
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(tone.color)
                Text(warning.message)
            }
        }
    }

    private var tone: CosignBannerTone {
        cosignWarningTone(for: warning.severity)
    }
}
