import Foundation
import Indexer
import Testing
@testable import Squads

struct EffectCrossCheckTests {
    // swiftlint:disable:next large_tuple
    private func sim(_ legs: [(AssetMovementLeg.Direction, String, String)]) -> AssetMovement {
        AssetMovement(legs: legs
            .map { AssetMovementLeg(direction: $0.0, amount: $0.1, asset: $0.2, counterparty: nil) })
    }

    private let usdcOut = ExpectedAssetMovementLeg(
        direction: .outflow, asset: .token(mint: "USDCMINT", symbol: "USDC", decimals: 6),
        amount: .exact(Decimal(1_500_000))
    )

    @Test func confirmedWhenAssetDirectionAndAmountMatch() {
        // Relay renders 1.5 USDC (display decimal) keyed by the MINT address; expected is 1_500_000 base units.
        let verdict = EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [usdcOut]),
            simulated: sim([(.outflow, "1.5", "USDCMINT")])
        )
        #expect(verdict == .confirmed)
    }

    @Test func confirmedWhenSimulatedLegUsesTheSymbol() {
        // The relay leg surfaces the SYMBOL ("USDC") rather than the mint address — the
        // identifier set matches either representation, so this still confirms.
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [usdcOut]),
            simulated: sim([(.outflow, "1.5", "USDC")])
        ) == .confirmed)
    }

    @Test func unconfirmedWhenSimulatedAssetsCannotBeCanonicalized() {
        // The simulated leg's asset is neither the mint, the symbol, nor SOL: we cannot
        // line the representations up, so fail safe to unconfirmed (never false-contradict).
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [usdcOut]),
            simulated: sim([(.outflow, "1.5", "SomeUnrecognizedAccount")])
        ) == .unconfirmed)
    }

    @Test func unconfirmedWhenSimulationAbsent() {
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [usdcOut]), simulated: AssetMovement(legs: [])
        ) == .unconfirmed)
    }

    @Test func unconfirmedWhenAssetUnresolved() {
        let leg = ExpectedAssetMovementLeg(direction: .outflow, asset: .unresolved, amount: .exact(Decimal(1)))
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [leg]), simulated: sim([(.outflow, "1.5", "USDCMINT")])
        ) == .unconfirmed)
    }

    @Test func contradictedWhenExpectedLegMissing() {
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [usdcOut]),
            simulated: sim([(.inflow, "1.5", "USDCMINT")]) // wrong direction
        ) == .contradicted)
    }

    @Test func contradictedWhenAmountDisagreesBeyondTolerance() {
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [usdcOut]),
            simulated: sim([(.outflow, "9.0", "USDCMINT")])
        ) == .contradicted)
    }

    @Test func solAtLeastAndSuffixParsing() {
        let solOut = ExpectedAssetMovementLeg(direction: .outflow, asset: .sol, amount: .exact(Decimal(2_000_000_000)))
        let poolIn = ExpectedAssetMovementLeg(
            direction: .inflow, asset: .token(mint: "JITO", symbol: "JitoSOL", decimals: 9),
            amount: .atLeast(Decimal(0))
        )
        let verdict = EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [solOut, poolIn]),
            simulated: sim([(.outflow, "2 SOL", "SOL"), (.inflow, "1.93", "JITO")])
        )
        #expect(verdict == .confirmed)
    }

    @Test func atMostConfirmsAtOrBelowTheBound() {
        // Price-limited partial-fill swap: the input leg moves at most the stated amount.
        let inputAtMost = ExpectedAssetMovementLeg(
            direction: .outflow, asset: .token(mint: "USDCMINT", symbol: "USDC", decimals: 6),
            amount: .atMost(Decimal(1_500_000))
        )
        // Below the bound (partial fill).
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [inputAtMost]),
            simulated: sim([(.outflow, "1.0", "USDCMINT")])
        ) == .confirmed)
        // Exactly at the bound (full fill).
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [inputAtMost]),
            simulated: sim([(.outflow, "1.5", "USDCMINT")])
        ) == .confirmed)
        // Just within tolerance above the bound (rounding/dust).
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [inputAtMost]),
            simulated: sim([(.outflow, "1.5001", "USDCMINT")])
        ) == .confirmed)
    }

    @Test func atMostContradictedWellAboveTheBound() {
        let inputAtMost = ExpectedAssetMovementLeg(
            direction: .outflow, asset: .token(mint: "USDCMINT", symbol: "USDC", decimals: 6),
            amount: .atMost(Decimal(1_500_000))
        )
        #expect(EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [inputAtMost]),
            simulated: sim([(.outflow, "9.0", "USDCMINT")])
        ) == .contradicted)
    }

    @Test func conditionalOnlyChecksApplicableLegs() {
        // aToB true: only the A-out / B-in legs are built by the builder, so a simulation
        // that moves A→B confirms even though the spec also declares the !aToB legs.
        let aOut = ExpectedAssetMovementLeg(
            direction: .outflow,
            asset: .token(mint: "A", symbol: "TKA", decimals: 6),
            amount: .exact(Decimal(1_000_000))
        )
        let bIn = ExpectedAssetMovementLeg(
            direction: .inflow,
            asset: .token(mint: "B", symbol: "TKB", decimals: 9),
            amount: .atLeast(Decimal(950_000_000))
        )
        let verdict = EffectCrossCheck.verdict(
            expected: ExpectedAssetMovement(legs: [aOut, bIn]),
            simulated: sim([(.outflow, "1", "A"), (.inflow, "0.96", "B")])
        )
        #expect(verdict == .confirmed)
    }
}
