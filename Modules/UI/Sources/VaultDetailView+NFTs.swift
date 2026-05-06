import Indexer
import Squads
import SwiftUI

extension VaultDetailView {
    @ViewBuilder
    func nftsSection(_ vault: VaultDetail) -> some View {
        let nfts = nfts(in: vault)

        if nfts.isEmpty {
            CosignEmptyState(key: .emptyNFTs)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.Vaults.nftsSection)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(nfts.enumerated()), id: \.element.id) { index, asset in
                            NFTAssetRow(asset: asset)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            if index < nfts.count - 1 {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }
}
