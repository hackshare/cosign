import Squads
import SwiftUI

extension ProposalDetailView {
    func proposalNavigationHeader(_ proposal: SquadProposalDetail? = nil) -> some View {
        CosignCompactPageHeader {
            coordinator.pop()
        } accessory: {
            if let url = proposal.flatMap(proposalNavigationURL) {
                CosignPlainGlyphButton(
                    glyph: .external,
                    accessibilityLabel: CosignCopy.ProposalDetail.openInExplorerAccessibilityLabel
                ) {
                    openURL(url)
                }
            }
        }
    }

    private func proposalNavigationURL(_ proposal: SquadProposalDetail) -> URL? {
        executionExplorerLink(for: proposal)?.url ?? manualSimulationLink(for: proposal)?.url
    }
}
