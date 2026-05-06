import Foundation
import Indexer
import Squads
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct VaultsListView: View {
    @Environment(Coordinator.self) private var coordinator

    private let squadAddress: String
    private let vaults: [VaultDetail]
    private let onViewMembers: (() -> Void)?

    init(squadAddress: String, vaults: [VaultDetail], onViewMembers: (() -> Void)? = nil) {
        self.squadAddress = squadAddress
        self.vaults = vaults
        self.onViewMembers = onViewMembers
    }

    var body: some View {
        if vaults.isEmpty {
            CosignEmptyState(key: .emptyVaults, primaryAction: onViewMembers)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.Vaults.sectionTitle)
                ForEach(Array(vaults.enumerated()), id: \.element.id) { index, vault in
                    CosignObjectRowButton {
                        coordinator.go(to: .vaultDetail(squad: squadAddress, vaultIndex: vault.ref.index))
                    } label: {
                        CosignVaultCard(vault: vault)
                    }
                    .accessibilityIdentifier("vault-row-\(index)")
                }
            }
        }
    }
}

struct CosignVaultCard: View {
    let vault: VaultDetail

    var body: some View {
        VaultRow(vault: vault)
    }
}

struct NativeTokenRow: View {
    let lamports: UInt64
    var trailingValue: String?

    var body: some View {
        HStack(spacing: 12) {
            TokenAvatar(
                localImageName: TokenArtwork.solAssetName,
                symbol: CosignCopy.Vaults.solSymbol,
                seed: "So11111111111111111111111111111111111111112"
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(CosignCopy.Vaults.solSymbol)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.Vaults.solBalanceSubtitle)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkFaint)
            }
            Spacer()
            Text(trailingValue ?? solAmount(lamports))
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.inkDim)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

func copyToPasteboard(_ value: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = value
    #endif
}

struct FungibleAssetRow: View {
    let asset: DASAsset
    var trailingValue: String?

    var body: some View {
        HStack(spacing: 12) {
            TokenAvatar(
                localImageName: TokenArtwork.localAssetName(for: asset),
                remoteURL: asset.imageURI,
                symbol: assetSymbol ?? normalized(asset.name),
                seed: asset.id
            )

            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(assetTitle)
                            .font(CosignTheme.FontStyle.titleM)
                            .foregroundStyle(CosignTheme.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                        if isToken2022(asset) {
                            Text(CosignCopy.Vaults.token2022Badge)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(CosignTheme.riskAmber)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                                .background(CosignTheme.riskAmber.opacity(0.10), in: .capsule)
                        }
                    }
                    if let subtitle = assetSubtitle {
                        Text(subtitle)
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkFaint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(trailingValue ?? displayAmount)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.inkDim)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private var assetSymbol: String? {
        normalized(asset.symbol)
    }

    private var assetTitle: String {
        assetSymbol ?? normalized(asset.name) ?? CosignCopy.Vaults.unknownToken
    }

    private var assetSubtitle: String? {
        guard let assetSymbol else {
            return CosignCopy.Vaults.mintSubtitle(shortAssetAddress(asset.id))
        }
        guard let assetName = normalized(asset.name), assetName != assetSymbol else {
            return nil
        }
        return assetName
    }

    private var displayAmount: String {
        let amount = formattedTokenAmount(
            rawAmount: asset.tokenAmount,
            displayAmount: asset.tokenDisplayAmount,
            decimals: asset.decimals
        )
        return CosignCopy.Vaults.tokenAmount(amount, symbol: assetSymbol)
    }
}

struct NFTAssetRow: View {
    let asset: DASAsset

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: asset.imageURI) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    CosignGlyphView(glyph: .image, size: 19, color: CosignTheme.inkFaint)
                case .empty:
                    ProgressView()
                @unknown default:
                    CosignGlyphView(glyph: .image, size: 19, color: CosignTheme.inkFaint)
                }
            }
            .frame(width: 44, height: 44)
            .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.small))
            .clipShape(.rect(cornerRadius: CosignTheme.Radius.small))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.name)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                    .lineLimit(1)
                if let symbol = asset.symbol, !symbol.isEmpty {
                    Text(symbol)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkFaint)
                        .lineLimit(1)
                }
                Text(asset.id)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }
}

func tokens(in vault: VaultDetail) -> [DASAsset] {
    vault.assets.filter { $0.kind == .fungible }
}

func nfts(in vault: VaultDetail) -> [DASAsset] {
    vault.assets.filter { $0.kind == .nft }
}

func solAmount(_ lamports: UInt64) -> String {
    "\(solQuantity(lamports)) SOL"
}

func solQuantity(_ lamports: UInt64) -> String {
    let sol = Decimal(lamports) / Decimal(1_000_000_000)
    return sol.formatted(.number.precision(.fractionLength(0 ... 9)))
}

func formattedTokenAmount(rawAmount: String?, displayAmount: String?, decimals: UInt8?) -> String {
    if let displayAmount, !displayAmount.isEmpty {
        return displayAmount
    }

    guard let rawAmount, !rawAmount.isEmpty else {
        return CosignCopy.Vaults.unknownAmount
    }

    guard let decimals, decimals > 0 else {
        return rawAmount
    }

    let isNegative = rawAmount.hasPrefix("-")
    let digits = String(rawAmount.drop(while: { $0 == "-" }))
    guard digits.allSatisfy(\.isNumber) else {
        return rawAmount
    }

    let decimalCount = Int(decimals)
    let paddedDigits: String = if digits.count <= decimalCount {
        String(repeating: "0", count: decimalCount - digits.count + 1) + digits
    } else {
        digits
    }

    let splitIndex = paddedDigits.index(paddedDigits.endIndex, offsetBy: -decimalCount)
    let whole = String(paddedDigits[..<splitIndex])
    var fraction = String(paddedDigits[splitIndex...])
    while fraction.last == "0" {
        fraction.removeLast()
    }

    let formatted = fraction.isEmpty ? whole : "\(whole).\(fraction)"
    return isNegative ? "-\(formatted)" : formatted
}

private struct VaultRow: View {
    let vault: VaultDetail

    var body: some View {
        CosignObjectRow(
            title: CosignCopy.Vaults.title(index: vault.ref.index),
            metadata: vault.ref.address,
            copyValue: vault.ref.address,
            copyAccessibilityLabel: CosignCopy.Vaults.copyVaultAddress,
            showsChevron: false,
            leading: {
                Text(CosignCopy.Vaults.indexBadge(index: vault.ref.index))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.ink)
                    .monospacedDigit()
                    .frame(width: 36, height: 36)
                    .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                            .stroke(CosignTheme.line, lineWidth: 1)
                    }
            },
            accessory: {
                Text(nativeBalanceText)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .monospacedDigit()
            },
            footer: {
                HStack(spacing: 5) {
                    HStack(spacing: 5) {
                        CosignGlyphView(glyph: .tokenGrid, size: 15, color: CosignTheme.inkFaint)
                        Text(CosignCopy.Vaults.tokenCount(tokenCount))
                    }
                    HStack(spacing: 5) {
                        CosignGlyphView(glyph: .image, size: 15, color: CosignTheme.inkFaint)
                        Text(CosignCopy.Vaults.nftCount(nftCount))
                    }
                    Spacer(minLength: 0)
                }
                .font(CosignTheme.FontStyle.caption)
                .foregroundStyle(CosignTheme.inkFaint)
            }
        )
    }

    private var tokenCount: Int {
        vault.assets.count(where: { $0.kind == .fungible })
    }

    private var nftCount: Int {
        vault.assets.count(where: { $0.kind == .nft })
    }

    private var nativeBalanceText: String {
        guard let nativeBalanceLamports = vault.nativeBalanceLamports else {
            return CosignCopy.Vaults.balanceUnavailable
        }
        return solAmount(nativeBalanceLamports)
    }
}

private func isToken2022(_ asset: DASAsset) -> Bool {
    asset.tokenProgramID?.hasPrefix("TokenzQdB") == true
}

private func normalized(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func shortAssetAddress(_ value: String) -> String {
    guard value.count > 12 else {
        return value
    }
    return "\(value.prefix(4))...\(value.suffix(4))"
}
