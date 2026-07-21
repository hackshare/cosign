import Foundation
import Indexer

public enum CrossCheckVerdict: Equatable, Sendable {
    case confirmed
    case unconfirmed
    case contradicted
}

public struct CrossCheckContext: Sendable {
    public let simulated: AssetMovement
    public let resolvedMints: [String: ResolvedMint]

    public init(simulated: AssetMovement, resolvedMints: [String: ResolvedMint]) {
        self.simulated = simulated
        self.resolvedMints = resolvedMints
    }
}

public enum EffectCrossCheck {
    /// 0.5% relative tolerance plus a 1-base-unit floor for exact-amount matches,
    /// absorbing decimal-formatting round-trips and dust. Re-validated against the
    /// captured golden simulations.
    static let relativeTolerance = Decimal(5) / Decimal(1000)

    public static func verdict(expected: ExpectedAssetMovement, simulated: AssetMovement) -> CrossCheckVerdict {
        guard !expected.legs.isEmpty else { return .unconfirmed }
        guard !simulated.legs.isEmpty else { return .unconfirmed }

        // The union of every expected leg's identifiers (plus "SOL"). A simulated leg
        // is "comparable" only if its asset is in this set — otherwise we cannot line
        // its representation up with anything the spec declares.
        let comparableAssets = canonicalAssetSet(expected)
        let simHasComparableLeg = simulated.legs.contains { comparableAssets.contains($0.asset) }

        var sawNotComparable = false
        for leg in expected.legs {
            switch evaluate(leg, simulated: simulated, simHasComparableLeg: simHasComparableLeg) {
            case .match: continue
            case .notComparable: sawNotComparable = true
            case .contradiction: return .contradicted
            }
        }
        return sawNotComparable ? .unconfirmed : .confirmed
    }

    private enum LegOutcome { case match, notComparable, contradiction }

    /// Every asset identifier the expected movement could match, so the comparator can
    /// tell "the simulation has recognizable legs but not this one" (a contradiction)
    /// from "we can't canonicalize the simulation at all" (not comparable).
    private static func canonicalAssetSet(_ expected: ExpectedAssetMovement) -> Set<String> {
        var set: Set = ["SOL"]
        for leg in expected.legs {
            set.formUnion(identifiers(for: leg.asset))
        }
        return set
    }

    private static func identifiers(for asset: ExpectedAsset) -> Set<String> {
        switch asset {
        case .sol: ["SOL"]
        case let .token(mint, symbol, _): Set([mint, symbol].filter { !$0.isEmpty })
        case .unresolved: []
        }
    }

    private static func evaluate(
        _ leg: ExpectedAssetMovementLeg,
        simulated: AssetMovement,
        simHasComparableLeg: Bool
    ) -> LegOutcome {
        if case .unresolved = leg.amount { return .notComparable }

        let decimals: Int
        switch leg.asset {
        case .sol: decimals = 9
        case let .token(_, _, mintDecimals): decimals = mintDecimals
        case .unresolved: return .notComparable
        }
        let ids = identifiers(for: leg.asset)
        guard !ids.isEmpty else { return .notComparable }

        // 1. Same-direction leg whose asset matches by mint OR symbol.
        let directional = simulated.legs.filter { $0.direction == leg.direction && ids.contains($0.asset) }
        if !directional.isEmpty {
            for candidate in directional {
                guard let simulatedBaseUnits = baseUnits(candidate.amount, decimals: decimals) else { continue }
                if satisfies(leg.amount, simulated: simulatedBaseUnits) { return .match }
            }
            return .contradiction // asset moved this direction but no amount agrees
        }

        // 2. The asset moved, but not in the expected direction → genuine disagreement.
        if simulated.legs.contains(where: { ids.contains($0.asset) }) { return .contradiction }

        // 3. This asset is absent from the simulation. Contradiction only if the
        //    simulation is otherwise comparable (has a recognizable leg); if we cannot
        //    canonicalize the simulation at all, fail safe to not-comparable.
        return simHasComparableLeg ? .contradiction : .notComparable
    }

    private static func satisfies(_ expected: ExpectedAmount, simulated: Decimal) -> Bool {
        switch expected {
        case .unresolved:
            false
        case let .exact(value):
            abs(simulated - value) <= max(Decimal(1), value * relativeTolerance)
        case let .atLeast(value):
            simulated >= value - max(Decimal(1), value * relativeTolerance)
        case let .atMost(value):
            simulated <= value + max(Decimal(1), value * relativeTolerance)
        }
    }

    /// Normalizes a relay display amount to base units. `"… base units"` is already
    /// base units; `"… SOL"` and bare decimals are display values scaled by 10^decimals.
    private static func baseUnits(_ amount: String, decimals: Int) -> Decimal? {
        let leading = amount.split(separator: " ").first.map(String.init) ?? amount
        guard let parsed = Decimal(string: leading) else { return nil }
        if amount.contains("base unit") { return parsed }
        return parsed * pow(Decimal(10), decimals)
    }
}
