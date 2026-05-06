import Indexer
import Squads
import SwiftUI

struct SigningActionSummary: View {
    let action: ActionObject
    let proposalAction: SquadProposalAction
    let approvalWouldReachThreshold: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                SeverityPill(severity: action.severity)
                ConfidencePill(confidence: action.confidence, source: action.source)
            }

            if let expectationChip {
                InspectionBadge(label: expectationChip, color: CosignTheme.accentDeep)
            }

            Text(CosignCopy.ProposalSigning.actionTitle(
                for: proposalAction,
                actionTitle: action.title
            ))
            .font(CosignTheme.FontStyle.display)
            .foregroundStyle(CosignTheme.ink)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)

            Text(CosignCopy.ProposalSigning.actionSubtitle(
                for: proposalAction,
                actionSubtitle: action.subtitle
            ))
            .font(CosignTheme.FontStyle.mono)
            .foregroundStyle(CosignTheme.inkDim)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(action.warnings, id: \.code) { warning in
                SignSheetWarningRow(warning: warning)
            }
        }
    }

    private var expectationChip: String? {
        CosignCopy.ProposalSigning.expectationChip(
            for: proposalAction,
            approvalWouldReachThreshold: approvalWouldReachThreshold
        )
    }
}

private struct SignSheetWarningRow: View {
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
