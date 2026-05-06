import Foundation
import Indexer
import Squads

struct SquadAssetSummary {
    let knownNativeBalanceLamports: UInt64
    let knownNativeBalanceCount: Int
    let tokenCount: Int
    let nftCount: Int

    var hasPriceableHoldings: Bool {
        knownNativeBalanceCount > 0 || tokenCount > 0 || nftCount > 0
    }
}

func assetSummary(for detail: SquadDetail) -> SquadAssetSummary {
    var knownNativeBalanceLamports: UInt64 = 0
    var knownNativeBalanceCount = 0
    var tokenCount = 0
    var nftCount = 0

    for vault in detail.vaults {
        if let nativeBalanceLamports = vault.nativeBalanceLamports {
            knownNativeBalanceLamports += nativeBalanceLamports
            knownNativeBalanceCount += 1
        }
        tokenCount += tokens(in: vault).count
        nftCount += nfts(in: vault).count
    }

    return SquadAssetSummary(
        knownNativeBalanceLamports: knownNativeBalanceLamports,
        knownNativeBalanceCount: knownNativeBalanceCount,
        tokenCount: tokenCount,
        nftCount: nftCount
    )
}

func nativeBalanceText(_ summary: SquadAssetSummary, vaultCount: Int) -> String {
    guard summary.knownNativeBalanceCount > 0 else {
        return CosignCopy.SquadDetail.unavailable
    }

    let formatted = solAmount(summary.knownNativeBalanceLamports)
    if summary.knownNativeBalanceCount == vaultCount {
        return formatted
    }
    return CosignCopy.SquadDetail.knownBalance(formatted)
}

func staleTransactionText(_ index: UInt64) -> String {
    CosignCopy.SquadDetail.staleTransaction(index: index)
}

func timeLockText(_ seconds: UInt32) -> String {
    CosignCopy.SquadDetail.timeLock(seconds: seconds)
}

func demoEstimatedUSDText(for summary: SquadAssetSummary) -> String? {
    demoEstimatedUSDText(lamports: summary.knownNativeBalanceLamports)
}

func demoEstimatedUSDText(lamports: UInt64) -> String? {
    guard let formatted = demoUSDValueText(lamports: lamports) else {
        return nil
    }
    return CosignCopy.SquadDetail.estimatedUSD(formatted)
}

func demoUSDValueText(lamports: UInt64) -> String? {
    guard lamports > 0 else {
        return nil
    }

    let sol = Decimal(lamports) / Decimal(1_000_000_000)
    let usd = sol * demoSolUSDPrice
    return formatDemoUSDValue(usd)
}

/// USD column value: the price when known, otherwise an em-dash — never blank,
/// never $0 (the holdings column always renders so the unit reads as a ledger).
func usdTrailing(_ value: String?) -> String {
    value ?? CosignCopy.VaultDetail.usdUnavailable
}

func demoUSDValueText(asset: DASAsset) -> String? {
    guard let amount = demoTokenAmount(asset),
          let symbol = asset.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    else {
        return nil
    }

    let usd: Decimal? = switch symbol {
    case "usdc":
        amount
    case "jto":
        amount * Decimal(613_576) / Decimal(1_000_000)
    case "hype":
        amount * Decimal(72_090_637) / Decimal(1_000_000)
    case "hnt":
        amount * Decimal(645_056) / Decimal(1_000_000)
    default:
        nil
    }

    guard let usd else {
        return nil
    }
    return formatDemoUSDValue(usd)
}

let cosignWrappedSolMint = "So11111111111111111111111111111111111111112"

/// Real-mode USD from a live price book (mint → USD, from the relay). Falls back
/// to the demo price model when `prices` is nil (the demo build), so demo output
/// is byte-for-byte unchanged.
func usdValueText(lamports: UInt64, prices: [String: Double]?) -> String? {
    guard let prices else {
        return demoUSDValueText(lamports: lamports)
    }
    guard lamports > 0, let solPrice = prices[cosignWrappedSolMint] else {
        return nil
    }
    let usd = Decimal(lamports) / Decimal(1_000_000_000) * Decimal(solPrice)
    return formatDemoUSDValue(usd)
}

func usdValueText(asset: DASAsset, prices: [String: Double]?) -> String? {
    guard let prices else {
        return demoUSDValueText(asset: asset)
    }
    guard let amount = demoTokenAmount(asset), let price = prices[asset.id] else {
        return nil
    }
    return formatDemoUSDValue(amount * Decimal(price))
}

func estimatedUSDText(lamports: UInt64, prices: [String: Double]?) -> String? {
    guard let formatted = usdValueText(lamports: lamports, prices: prices) else {
        return nil
    }
    return CosignCopy.SquadDetail.estimatedUSD(formatted)
}

private let demoSolUSDPrice = Decimal(159_392_295_227_591) / Decimal(1_000_000_000_000)

private func formatDemoUSDValue(_ value: Decimal) -> String? {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = CosignCopy.SquadDetail.usdSymbol
    formatter.currencySymbol = "$"
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 2
    guard let formatted = formatter.string(from: NSDecimalNumber(decimal: value)) else {
        return nil
    }
    return formatted
}

private func demoTokenAmount(_ asset: DASAsset) -> Decimal? {
    if let amount = decimalFromDemoDisplay(asset.tokenDisplayAmount) {
        return amount
    }

    guard let rawAmount = asset.tokenAmount,
          let rawDecimal = Decimal(string: rawAmount),
          let decimals = asset.decimals
    else {
        return nil
    }

    let divisor = pow10(decimals)
    return rawDecimal / divisor
}

private func decimalFromDemoDisplay(_ value: String?) -> Decimal? {
    guard var normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !normalized.isEmpty
    else {
        return nil
    }

    normalized = normalized.replacingOccurrences(of: ",", with: "")
    let uppercased = normalized.uppercased()
    let multiplier: Decimal
    if uppercased.hasSuffix("M") {
        multiplier = Decimal(1_000_000)
        normalized.removeLast()
    } else if uppercased.hasSuffix("K") {
        multiplier = Decimal(1000)
        normalized.removeLast()
    } else {
        multiplier = Decimal(1)
    }

    guard let amount = Decimal(string: normalized) else {
        return nil
    }
    return amount * multiplier
}

private func pow10(_ exponent: UInt8) -> Decimal {
    guard exponent > 0 else {
        return Decimal(1)
    }
    return (0 ..< exponent).reduce(Decimal(1)) { result, _ in
        result * Decimal(10)
    }
}
