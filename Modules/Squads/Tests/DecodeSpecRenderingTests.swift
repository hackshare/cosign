import Indexer
import Testing
@testable import Squads

struct DecodeSpecRenderingTests {
    @Test func predicateHoldsForMatchingBools() {
        let args: [String: DecodedArgValue] = ["aToB": .bool(true), "x": .bool(false)]
        #expect(WhenPredicate.holds([], args: args))
        #expect(WhenPredicate.holds(["arg(aToB)"], args: args))
        #expect(WhenPredicate.holds(["!arg(x)"], args: args))
        #expect(WhenPredicate.holds(["arg(aToB)", "!arg(x)"], args: args))
        #expect(!WhenPredicate.holds(["!arg(aToB)"], args: args))
        #expect(!WhenPredicate.holds(["arg(missing)"], args: args))
    }

    private func variant(_ when: [String], _ text: String) -> DecodeSpec.TemplateVariant {
        DecodeSpec.TemplateVariant(when: when, text: text)
    }

    @Test func selectsConditionalVariant() {
        let renderer = DecodeSpecTemplateRenderer()
        let variants = [variant(["arg(aToB)"], "A to B"), variant(["!arg(aToB)"], "B to A")]
        #expect(renderer
            .render(variants, args: ["aToB": .bool(false)], accounts: [], roleIndexes: [:], mints: [:]) == "B to A")
    }

    @Test func rendersTokenAmountWhenMintResolved() {
        let renderer = DecodeSpecTemplateRenderer()
        let variants = [variant([], "Deposit {amount:token(mint)}")]
        let out = renderer.render(
            variants,
            args: ["amount": .uint(1_000_000)],
            accounts: ["prog", "MINTADDR"],
            roleIndexes: ["mint": 1],
            mints: ["MINTADDR": MintInfo(symbol: "USDC", decimals: 6)]
        )
        #expect(out == "Deposit 1 USDC")
    }

    @Test func failsOpenToRawWhenMintUnresolved() {
        let renderer = DecodeSpecTemplateRenderer()
        let variants = [variant([], "Deposit {amount:token(mint)}")]
        let out = renderer.render(
            variants,
            args: ["amount": .uint(1_000_000)],
            accounts: ["prog", "SoMeLongMintAddress1111111111111111111111111"],
            roleIndexes: ["mint": 1],
            mints: [:]
        )
        #expect(out?.contains("1000000") == true)
    }

    @Test func rendersSolAndRawArg() {
        let renderer = DecodeSpecTemplateRenderer()
        #expect(renderer.render(
            [variant([], "Stake {lamports:sol}")],
            args: ["lamports": .uint(2_000_000_000)],
            accounts: [],
            roleIndexes: [:],
            mints: [:]
        ) == "Stake 2 SOL")
        #expect(renderer.render(
            [variant([], "n={count}")],
            args: ["count": .uint(3)],
            accounts: [],
            roleIndexes: [:],
            mints: [:]
        ) == "n=3")
    }

    @Test func negativeDecimalsFailOpenWithoutCrashing() {
        let renderer = DecodeSpecTemplateRenderer()
        let out = renderer.render(
            [variant([], "Deposit {amount:token(mint)}")],
            args: ["amount": .uint(5)],
            accounts: ["prog", "MINTX"],
            roleIndexes: ["mint": 1],
            mints: ["MINTX": MintInfo(symbol: "X", decimals: -5)]
        )
        #expect(out == "Deposit 5 X")
    }

    @Test func emptyOrColonOnlyTemplateTokenFailsOpenWithoutCrashing() {
        let renderer = DecodeSpecTemplateRenderer()
        #expect(renderer.render(
            [variant([], "Send {} now")], args: [:], accounts: [], roleIndexes: [:], mints: [:]
        ) == "Send ? now")
        #expect(renderer.render(
            [variant([], "x {:} y")], args: [:], accounts: [], roleIndexes: [:], mints: [:]
        ) == "x ? y")
    }

    @Test func nonBoolWhenArgSelectsNoVariantRegardlessOfNegation() {
        let renderer = DecodeSpecTemplateRenderer()
        let variants = [variant(["arg(side)"], "A to B"), variant(["!arg(side)"], "B to A")]
        #expect(renderer
            .render(variants, args: ["side": .uint(1)], accounts: [], roleIndexes: [:], mints: [:]) == nil)
        #expect(renderer
            .render(variants, args: ["side": .uint(0)], accounts: [], roleIndexes: [:], mints: [:]) == nil)
    }

    @Test func rendersMintSymbolForRoleTokenFormatter() {
        let renderer = DecodeSpecTemplateRenderer()
        let out = renderer.render(
            [variant([], "pool {poolMint:token}")],
            args: [:],
            accounts: ["prog", "MINTY"],
            roleIndexes: ["poolMint": 1],
            mints: ["MINTY": MintInfo(symbol: "mSOL", decimals: 9)]
        )
        #expect(out == "pool mSOL")
    }
}
