import Squads
import SwiftUI

struct ProposalActionButtonLabel: View {
    let action: SquadProposalAction
    var showsFinalSignerNote = true
    var isHighRisk = false

    var body: some View {
        HStack {
            CosignGlyphView(
                glyph: isHighRiskApproval ? .shield : action.glyph,
                size: 16,
                color: isHighRiskApproval ? CosignTheme.riskRed : CosignTheme.ink
            )
            Text(
                isHighRiskApproval
                    ? CosignCopy.ProposalActions.reviewToApproveTitle
                    : CosignCopy.ProposalActions.actionTitle(for: action)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            Spacer()
            if action == .approveAndExecute, showsFinalSignerNote, !isHighRiskApproval {
                Text(CosignCopy.ProposalActions.finalSignerNote)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
            }
        }
    }

    private var isHighRiskApproval: Bool {
        isHighRisk && (action == .approve || action == .approveAndExecute || action == .execute)
    }
}

struct ProposalMoreActionsButtonLabel: View {
    var body: some View {
        HStack(spacing: 7) {
            CosignGlyphView(glyph: .list, size: 15, color: CosignTheme.ink)
            Text(CosignCopy.ProposalActions.moreActionsTitle)
                .font(CosignTheme.FontStyle.body)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
    }
}
