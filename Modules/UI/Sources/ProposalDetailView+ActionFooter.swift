import Indexer
import Squads
import SwiftUI

extension ProposalDetailView {
    @ViewBuilder
    func stickyActionFooter(_ proposal: SquadProposalDetail) -> some View {
        if proposal.isTerminal {
            ProposalTerminalFooter(
                explorerURL: terminalExplorerURL(for: proposal),
                rawURL: terminalRawURL(for: proposal),
                explorerIsPrimary: proposal.isExecuted
            )
        } else {
            ProposalStickyActionFooter(
                proposal: proposal,
                signers: actionSigners,
                selectedSignerID: selectedSignerID,
                squadMembers: squadMembers,
                isSubmittingAction: isSubmittingAction,
                isHighRisk: proposalActionObject(for: proposal).severity == .high
            ) { action, signer in
                beginSigning(action: action, signer: signer)
            }
        }
    }

    private func terminalExplorerURL(for proposal: SquadProposalDetail) -> URL? {
        let rpcURL = indexerEnvironment.effectiveExplorerRPCURL
        if proposal.isExecuted, let executionSignature {
            return SolanaExplorer.transactionURL(signature: executionSignature, rpcURL: rpcURL)
        }
        if let address = proposal.transactionAddress {
            return SolanaExplorer.addressURL(address: address, rpcURL: rpcURL)
        }
        return nil
    }

    private func terminalRawURL(for proposal: SquadProposalDetail) -> URL? {
        guard let address = proposal.transactionAddress else {
            return nil
        }
        return SolanaExplorer.squadsTransactionInspectorURL(
            transactionAddress: address,
            rpcURL: indexerEnvironment.effectiveExplorerRPCURL
        )
    }
}
