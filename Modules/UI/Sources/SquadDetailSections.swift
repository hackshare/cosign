import Indexer
import Squads
import SwiftUI

enum SquadDetailTab: CaseIterable, Identifiable {
    case vaults
    case proposals
    case activity
    case members

    var id: Self {
        self
    }
}

enum VaultAssetTab: CaseIterable, Identifiable {
    case tokens
    case nfts

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .tokens:
            CosignCopy.SquadDetail.tokensMetric
        case .nfts:
            CosignCopy.SquadDetail.nftsMetric
        }
    }
}

struct SingleVaultDetailSection: View {
    @Environment(Coordinator.self) private var coordinator

    let squadAddress: String
    let vault: VaultDetail
    var prices: [String: Double]?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.Vaults.title(index: vault.ref.index))
            CosignObjectRowButton {
                coordinator.go(to: .vaultDetail(squad: squadAddress, vaultIndex: vault.ref.index))
            } label: {
                CosignVaultCard(vault: vault)
            }
            .accessibilityIdentifier("vault-row-\(vault.ref.index)")
        }

        vaultHoldingsSection
        vaultNFTsSection
    }

    @ViewBuilder
    private var vaultHoldingsSection: some View {
        let vaultTokens = tokens(in: vault)
        if vault.nativeBalanceLamports != nil || !vaultTokens.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(
                    title: CosignCopy.Vaults.holdingsSection,
                    trailing: CosignCopy.VaultDetail.usdValueColumn
                )
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        if let nativeBalanceLamports = vault.nativeBalanceLamports {
                            NativeTokenRow(
                                lamports: nativeBalanceLamports,
                                trailingValue: usdTrailing(usdValueText(
                                    lamports: nativeBalanceLamports,
                                    prices: prices
                                ))
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        ForEach(Array(vaultTokens.enumerated()), id: \.element.id) { index, asset in
                            if index > 0 || vault.nativeBalanceLamports != nil {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                            FungibleAssetRow(
                                asset: asset,
                                trailingValue: usdTrailing(usdValueText(asset: asset, prices: prices))
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        } else {
            CosignEmptyState(key: .emptyTokens)
        }
    }

    @ViewBuilder
    private var vaultNFTsSection: some View {
        let vaultNFTs = nfts(in: vault)
        if !vaultNFTs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.Vaults.nftsSection)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(vaultNFTs.enumerated()), id: \.element.id) { index, asset in
                            NFTAssetRow(asset: asset)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            if index < vaultNFTs.count - 1 {
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

extension SquadDetailView {
    @ViewBuilder
    func membersSection(_ members: [SquadMember]) -> some View {
        if members.isEmpty {
            CosignEmptyState(
                title: CosignCopy.SquadDetail.noMembersTitle,
                systemImage: "person.slash",
                message: CosignCopy.SquadDetail.noMembersMessage
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.SquadDetail.membersSection)
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            CosignObjectNavigationLink(value: Route.signerSquads(member.pubkey)) {
                                MemberRow(member: member)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                            }

                            if index < members.count - 1 {
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

struct MemberRow: View {
    let member: SquadMember

    var body: some View {
        CosignObjectRow(
            title: cosignShortAddress(member.pubkey, prefix: 6, suffix: 6),
            metadata: member.pubkey,
            copyValue: member.pubkey,
            copyAccessibilityLabel: CosignCopy.Squads.copyMemberAddress,
            style: .plain,
            footer: {
                HStack(spacing: 6) {
                    PermissionBadge(title: CosignCopy.SquadDetail.initiatePermission, isEnabled: member.canInitiate)
                    PermissionBadge(title: CosignCopy.SquadDetail.votePermission, isEnabled: member.canVote)
                    PermissionBadge(title: CosignCopy.SquadDetail.executePermission, isEnabled: member.canExecute)
                    Spacer(minLength: 0)
                }
            }
        )
    }
}

private struct PermissionBadge: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(isEnabled ? CosignTheme.accentDeep : CosignTheme.inkFaint)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                isEnabled ? CosignTheme.accentWash : CosignTheme.surface2,
                in: .rect(cornerRadius: CosignTheme.Radius.small)
            )
    }
}
