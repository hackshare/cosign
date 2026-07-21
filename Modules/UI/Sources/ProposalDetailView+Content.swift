import Indexer
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
            contradictionBanner(for: proposal)
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

extension ProposalDetailView {
    func decodedInstructions(for proposal: SquadProposalDetail) -> [DecodedInstructionDisplay] {
        instructionDecoder.decode(
            proposal, idls: resolvedIDLs, specs: resolvedSpecs,
            mints: decodeMintInfo, crossCheck: crossCheckContext(for: proposal)
        )
    }

    var decodeMintInfo: [String: MintInfo] {
        resolvedMints.mapValues { MintInfo(symbol: $0.symbol ?? cosignShortAddress($0.mint), decimals: $0.decimals) }
    }

    func crossCheckContext(for proposal: SquadProposalDetail) -> CrossCheckContext? {
        let effects = (proposal.isExecuted ? executedInspectionReport?.action : inspectionReport?.action)?.effects
        return proposalCrossCheckContext(
            instructionCount: proposal.instructions.count,
            effects: effects,
            ownVaultAccounts: ownVaultAccounts,
            resolvedMints: resolvedMints
        )
    }

    @ViewBuilder
    func contradictionBanner(for proposal: SquadProposalDetail) -> some View {
        if decodedInstructions(for: proposal).contains(where: { $0.crossCheck == .contradicted }) {
            CosignInlineBanner(tone: .amber) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CosignCopy.ProposalDetail.contradictionBannerTitle).font(CosignTheme.FontStyle.titleM)
                    Text(CosignCopy.ProposalDetail.contradictionBannerMessage).font(CosignTheme.FontStyle.caption)
                }
            }
        }
    }
}

/// Builds the effect cross-check context for a proposal, or nil when no meaningful verdict is
/// possible. Returns nil for multi-instruction proposals: the relay reports transaction-wide
/// effects with no per-instruction attribution, so an aggregate simulation leg could confirm the
/// wrong instruction (adding legs only biases toward Confirm, the dangerous direction). Scoped to
/// single-instruction proposals until the relay tags effects by instruction index.
func proposalCrossCheckContext(
    instructionCount: Int,
    effects: [RelayInspectionEffect]?,
    ownVaultAccounts: Set<String>,
    resolvedMints: [String: ResolvedMint]
) -> CrossCheckContext? {
    guard instructionCount == 1, let effects, !effects.isEmpty else { return nil }
    return CrossCheckContext(
        simulated: AssetMovement.build(from: effects, ownAccounts: ownVaultAccounts),
        resolvedMints: resolvedMints
    )
}
