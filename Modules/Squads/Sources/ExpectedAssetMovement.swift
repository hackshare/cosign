import Foundation
import Indexer

public enum ExpectedAsset: Equatable, Sendable {
    case sol
    /// Carries both identifiers the relay might emit for the leg — the mint address
    /// (SPL-transfer CPIs) and the symbol (demo fixtures / well-known tokens) — plus
    /// the decimals used to normalize the relay's display amount.
    case token(mint: String, symbol: String, decimals: Int)
    case unresolved
}

public enum ExpectedAmount: Equatable, Sendable {
    case exact(Decimal)
    case atLeast(Decimal)
    case atMost(Decimal)
    case unresolved
}

public struct ExpectedAssetMovementLeg: Equatable, Sendable {
    public let direction: AssetMovementLeg.Direction
    public let asset: ExpectedAsset
    public let amount: ExpectedAmount

    public init(direction: AssetMovementLeg.Direction, asset: ExpectedAsset, amount: ExpectedAmount) {
        self.direction = direction
        self.asset = asset
        self.amount = amount
    }
}

public struct ExpectedAssetMovement: Equatable, Sendable {
    public let legs: [ExpectedAssetMovementLeg]

    public init(legs: [ExpectedAssetMovementLeg]) {
        self.legs = legs
    }
}

public enum ExpectedAssetMovementBuilder {
    public static func build(
        spec: DecodeSpec,
        args: [String: DecodedArgValue],
        accounts: [String],
        resolvedMints: [String: ResolvedMint]
    ) -> ExpectedAssetMovement {
        var legs = [ExpectedAssetMovementLeg]()
        for effect in spec.effects where WhenPredicate.holds(effect.when, args: args) {
            let direction: AssetMovementLeg.Direction = effect.direction == .out ? .outflow : .inflow
            let asset = resolveAsset(
                effect.asset, roleIndexes: spec.accounts, accounts: accounts, resolvedMints: resolvedMints
            )
            legs.append(ExpectedAssetMovementLeg(
                direction: direction,
                asset: asset,
                amount: resolveAmount(effect, args: args)
            ))
        }
        return ExpectedAssetMovement(legs: legs)
    }

    private static func resolveAsset(
        _ asset: String,
        roleIndexes: [String: Int],
        accounts: [String],
        resolvedMints: [String: ResolvedMint]
    ) -> ExpectedAsset {
        if asset == "SOL" { return .sol }
        guard asset.hasPrefix("token("), asset.hasSuffix(")") else { return .unresolved }
        let role = String(asset.dropFirst(6).dropLast())
        guard let index = roleIndexes[role], accounts.indices.contains(index),
              let resolved = resolvedMints[accounts[index]]
        else { return .unresolved }
        return .token(mint: resolved.mint, symbol: resolved.symbol ?? "", decimals: resolved.decimals)
    }

    private static func resolveAmount(_ effect: DecodeSpec.Effect, args: [String: DecodedArgValue]) -> ExpectedAmount {
        if let reference = effect.amount {
            return baseUnits(reference, args: args).map(ExpectedAmount.exact) ?? .unresolved
        }
        if let reference = effect.amountAtLeast {
            return baseUnits(reference, args: args).map(ExpectedAmount.atLeast) ?? .unresolved
        }
        if let reference = effect.amountAtMost {
            return baseUnits(reference, args: args).map(ExpectedAmount.atMost) ?? .unresolved
        }
        return .unresolved
    }

    /// A reference is `arg(name)` (a decoded unsigned base-unit value) or a literal
    /// non-negative integer (e.g. "0"). Anything else is unresolvable.
    private static func baseUnits(_ reference: String, args: [String: DecodedArgValue]) -> Decimal? {
        if reference.hasPrefix("arg("), reference.hasSuffix(")") {
            let name = String(reference.dropFirst(4).dropLast())
            guard case let .uint(value)? = args[name] else { return nil }
            return Decimal(value)
        }
        return UInt64(reference).map(Decimal.init)
    }
}
