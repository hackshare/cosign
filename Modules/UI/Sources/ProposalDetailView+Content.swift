import Squads
import SwiftUI

extension ProposalDetailView {
    func proposalContent(_ proposal: SquadProposalDetail) -> some View {
        CosignScreen(bottomPadding: proposalBottomPadding(for: proposal)) {
            proposalNavigationHeader(proposal)
            proposalDecisionSection(proposal)
            if proposal.isExecuted, executionFailed {
                CosignInlineBanner(tone: .red) {
                    Text(CosignCopy.ProposalDetail.executionFailed)
                }
            }
            votesSection(proposal)
            actionsSection(proposal)
            decodedFieldsSection(proposal)
            movementSection(for: proposal)
            inspectionSection(proposal)
            linksSection(proposal)
            technicalDetailsSection(proposal)
            votersSection(title: CosignCopy.ProposalDetail.approvalsSectionTitle, addresses: proposal.votersYes)
            votersSection(title: CosignCopy.ProposalDetail.rejectionsSectionTitle, addresses: proposal.votersNo)
            votersSection(
                title: CosignCopy.ProposalDetail.cancellationsSectionTitle,
                addresses: proposal.votersCancelled
            )
        }
    }

    private func proposalBottomPadding(for proposal: SquadProposalDetail) -> CGFloat {
        proposal.canBeActedOn ?
            CosignLayout.screenBottomPadding(stickyFooterHeight: stickyFooterHeight) :
            CosignLayout.screenBottomPadding
    }
}
