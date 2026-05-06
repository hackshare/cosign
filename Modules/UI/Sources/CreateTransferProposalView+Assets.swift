import CosignCore
import Squads
import SwiftUI

extension CreateTransferProposalView {
    var transferAssets: [ProposalCreationAsset] {
        guard let selectedVault else {
            return [.sol]
        }

        let tokenAssets = tokens(in: selectedVault)
            .compactMap(ProposalCreationAsset.init(asset:))
            .filter(\.isTransferSupported)
        return [.sol] + tokenAssets
    }

    var unsupportedTransferTokenCount: Int {
        guard let selectedVault else {
            return 0
        }

        return tokens(in: selectedVault)
            .compactMap(ProposalCreationAsset.init(asset:))
            .count(where: { !$0.isTransferSupported })
    }

    var selectedAsset: ProposalCreationAsset? {
        transferAssets.first { $0.id == selectedAssetID } ?? transferAssets.first
    }

    var assetSelection: Binding<String> {
        Binding(
            get: { selectedAsset?.id ?? ProposalCreationAsset.sol.id },
            set: { selectedAssetID = $0 }
        )
    }

    var selectedAssetBalanceBaseUnits: UInt64? {
        guard let selectedAsset else {
            return nil
        }
        if selectedAsset.id == ProposalCreationAsset.sol.id {
            return selectedVault?.nativeBalanceLamports
        }
        return selectedAsset.balanceBaseUnits
    }

    func selectedAssetBalanceText(_ asset: ProposalCreationAsset) -> String {
        if asset.id == ProposalCreationAsset.sol.id {
            return selectedVault?.nativeBalanceLamports.map(solAmount) ?? CosignCopy.SquadDetail.unavailable
        }
        return formattedTokenAmount(
            rawAmount: asset.rawAmount,
            displayAmount: nil,
            decimals: asset.decimals
        )
    }

    func transferDraft(
        asset: ProposalCreationAsset,
        vault: VaultDetail,
        amount: UInt64
    ) -> TransferProposalDraft {
        guard let mint = asset.mint, let tokenProgramID = asset.tokenProgramID else {
            return .sol(SOLTransferProposalDraft(
                vaultIndex: vault.ref.index,
                recipient: trimmedRecipient,
                lamports: amount,
                memo: trimmedMemo
            ))
        }

        return .token(TokenTransferProposalDraft(
            vaultIndex: vault.ref.index,
            recipientOwner: trimmedRecipient,
            mint: mint,
            amount: amount,
            decimals: asset.decimals,
            tokenProgramID: tokenProgramID,
            memo: trimmedMemo
        ))
    }

    func tokenDetails(
        asset: ProposalCreationAsset,
        vault: VaultDetail,
        amount: UInt64
    ) throws -> ProposalCreationTokenDetails? {
        guard let mint = asset.mint, let tokenProgramID = asset.tokenProgramID else {
            return nil
        }

        return try ProposalCreationTokenDetails(
            programLabel: tokenProgramLabel(tokenProgramID),
            mint: mint,
            sourceTokenAccount: CosignCore.deriveAssociatedTokenAccountAddress(
                owner: vault.ref.address,
                mint: mint,
                tokenProgramID: tokenProgramID
            ),
            destinationTokenAccount: CosignCore.deriveAssociatedTokenAccountAddress(
                owner: trimmedRecipient,
                mint: mint,
                tokenProgramID: tokenProgramID
            ),
            baseUnits: amount
        )
    }

    func amountText(for asset: ProposalCreationAsset, amount: UInt64) -> String {
        if asset.id == ProposalCreationAsset.sol.id {
            return solAmount(amount)
        }

        let displayAmount = formattedTokenAmount(
            rawAmount: String(amount),
            displayAmount: nil,
            decimals: asset.decimals
        )
        return "\(displayAmount) \(asset.title)"
    }
}
