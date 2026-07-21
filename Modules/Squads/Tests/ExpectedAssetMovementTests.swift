import Foundation
import Indexer
import Testing
@testable import Squads

struct ExpectedAssetMovementTests {
    private func spec(_ json: String) throws -> DecodeSpec {
        try JSONDecoder().decode(DecodeSpec.self, from: Data(json.utf8))
    }

    @Test func buildsSingleOutflowFromArgAndResolvedMint() throws {
        let decoded = try spec(#"""
        { "program":"P","discriminator":[1],"mode":"standalone","layout":[],"action":"Deposit",
          "accounts":{"src":0},"template":"x",
          "effects":[{"direction":"out","asset":"token(src)","amount":"arg(amt)"}] }
        """#)
        let movement = ExpectedAssetMovementBuilder.build(
            spec: decoded,
            args: ["amt": .uint(1_500_000)],
            accounts: ["USDCACC"],
            resolvedMints: ["USDCACC": ResolvedMint(mint: "USDCMINT", decimals: 6, symbol: "USDC")]
        )
        #expect(movement.legs.count == 1)
        #expect(movement.legs[0].direction == .outflow)
        #expect(movement.legs[0].asset == .token(mint: "USDCMINT", symbol: "USDC", decimals: 6))
        #expect(movement.legs[0].amount == .exact(Decimal(1_500_000)))
    }

    @Test func excludesWhenFalseEffectsAndFlipsSolAtLeast() throws {
        let decoded = try spec(#"""
        { "program":"P","discriminator":[14],"mode":"standalone","layout":[],"action":"Stake",
          "accounts":{"poolMint":2},"template":"x",
          "effects":[
            {"direction":"out","asset":"SOL","amount":"arg(lamports)"},
            {"direction":"in","asset":"token(poolMint)","amountAtLeast":"0"},
            {"when":["arg(never)"],"direction":"out","asset":"SOL","amount":"arg(lamports)"}
          ] }
        """#)
        let movement = ExpectedAssetMovementBuilder.build(
            spec: decoded,
            args: ["lamports": .uint(2_000_000_000)],
            accounts: ["v", "x", "POOLMINT"],
            resolvedMints: ["POOLMINT": ResolvedMint(mint: "POOLMINT", decimals: 9, symbol: "JitoSOL")]
        )
        #expect(movement.legs.count == 2)
        #expect(movement.legs[0] == ExpectedAssetMovementLeg(
            direction: .outflow,
            asset: .sol,
            amount: .exact(Decimal(2_000_000_000))
        ))
        #expect(movement.legs[1].asset == .token(mint: "POOLMINT", symbol: "JitoSOL", decimals: 9))
        #expect(movement.legs[1].amount == .atLeast(Decimal(0)))
    }

    @Test func amountAtMostResolvesFromArgAndLiteral() throws {
        let decoded = try spec(#"""
        { "program":"P","discriminator":[1],"mode":"standalone","layout":[],"action":"Swap",
          "accounts":{"src":0,"dst":1},"template":"x",
          "effects":[
            {"direction":"out","asset":"token(src)","amountAtMost":"arg(maxIn)"},
            {"direction":"in","asset":"token(dst)","amountAtMost":"0"}
          ] }
        """#)
        let movement = ExpectedAssetMovementBuilder.build(
            spec: decoded,
            args: ["maxIn": .uint(1_500_000)],
            accounts: ["USDCACC", "SOLACC"],
            resolvedMints: [
                "USDCACC": ResolvedMint(mint: "USDCMINT", decimals: 6, symbol: "USDC"),
                "SOLACC": ResolvedMint(mint: "SOLMINT", decimals: 9, symbol: "SOL")
            ]
        )
        #expect(movement.legs.count == 2)
        #expect(movement.legs[0].amount == .atMost(Decimal(1_500_000)))
        #expect(movement.legs[1].amount == .atMost(Decimal(0)))
    }

    @Test func unresolvedMintAndMissingArgDegradeGracefully() throws {
        let decoded = try spec(#"""
        { "program":"P","discriminator":[1],"mode":"standalone","layout":[],"action":"Deposit",
          "accounts":{"src":0},"template":"x",
          "effects":[{"direction":"out","asset":"token(src)","amount":"arg(missing)"}] }
        """#)
        let movement = ExpectedAssetMovementBuilder.build(
            spec: decoded, args: [:], accounts: ["ACC"], resolvedMints: [:]
        )
        #expect(movement.legs[0].asset == .unresolved)
        #expect(movement.legs[0].amount == .unresolved)
    }
}
