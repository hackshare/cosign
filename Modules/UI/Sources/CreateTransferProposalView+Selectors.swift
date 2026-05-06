import Squads
import SwiftUI

extension CreateTransferProposalView {
    func presentSelector(_ selector: TransferProposalSelector) {
        focusedInput = nil
        switch selector {
        case .signer:
            showsSignerSelector = true
        case .vault:
            showsVaultSelector = true
        case .asset:
            showsAssetSelector = true
        }
    }

    func dismissSelector(_ selector: TransferProposalSelector) {
        switch selector {
        case .signer:
            showsSignerSelector = false
        case .vault:
            showsVaultSelector = false
        case .asset:
            showsAssetSelector = false
        }
    }

    var signerSelectorSheet: some View {
        CosignSelectorSheet(
            title: CosignCopy.ProposalCreation.selectSignerTitle,
            subtitle: CosignCopy.ProposalCreation.selectSignerSubtitle,
            options: actionSigners.map(signerOption),
            selection: signerIDSelection,
            onDismiss: { dismissSelector(.signer) }
        )
    }

    @ViewBuilder
    var vaultSelectorSheet: some View {
        if let detail {
            CosignSelectorSheet(
                title: CosignCopy.ProposalCreation.selectVaultTitle,
                subtitle: CosignCopy.ProposalCreation.selectVaultSubtitle,
                options: detail.vaults.map(vaultOption),
                selection: vaultIndexSelection,
                onDismiss: { dismissSelector(.vault) }
            )
        }
    }

    var assetSelectorSheet: some View {
        CosignSelectorSheet(
            title: CosignCopy.ProposalCreation.selectAssetTitle,
            subtitle: CosignCopy.ProposalCreation.selectAssetSubtitle,
            options: transferAssets.map(assetOption),
            selection: assetSelection,
            onDismiss: { dismissSelector(.asset) }
        )
    }

    var signerIDSelection: Binding<UUID> {
        Binding(
            get: { selectedSigner?.id ?? actionSigners.first?.id ?? UUID() },
            set: { selectedSignerID = $0 }
        )
    }

    var vaultIndexSelection: Binding<UInt8> {
        Binding(
            get: { selectedVault?.ref.index ?? selectedVaultIndex ?? 0 },
            set: { selectVault($0) }
        )
    }

    private func selectVault(_ index: UInt8) {
        selectedVaultIndex = index
        selectedAssetID = ProposalCreationAsset.sol.id
    }

    private func signerOption(_ signer: ProposalActionSigner) -> CosignSelectorOption<UUID> {
        CosignSelectorOption(
            id: signer.id,
            title: signer.label,
            subtitle: signer.type.displayName,
            detail: cosignShortAddress(signer.address),
            glyph: .key
        )
    }

    private func vaultOption(_ vault: VaultDetail) -> CosignSelectorOption<UInt8> {
        CosignSelectorOption(
            id: vault.ref.index,
            title: CosignCopy.ProposalCreation.vaultDisplayName(index: vault.ref.index),
            subtitle: vault.nativeBalanceLamports.map(solAmount) ?? CosignCopy.Vaults.balanceUnavailable,
            detail: cosignShortAddress(vault.ref.address),
            glyph: .shield
        )
    }

    private func assetOption(_ asset: ProposalCreationAsset) -> CosignSelectorOption<String> {
        CosignSelectorOption(
            id: asset.id,
            title: asset.title,
            subtitle: selectedAssetBalanceText(asset),
            detail: asset.programDetail,
            glyph: asset.glyph
        )
    }
}
