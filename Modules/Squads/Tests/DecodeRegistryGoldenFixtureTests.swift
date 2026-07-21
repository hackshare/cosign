import Foundation
import Indexer
import Testing
@testable import Squads

// Program ids and mint addresses used by the fixtures (real mainnet values).
private let kaminoProgram = "KLend2g3cP87fffoy8q1mQqGKjrxjC8boSyAYavgmjD"
private let stakePoolProgram = "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy"
private let orcaProgram = "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc"
private let raydiumProgram = "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8"
private let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
private let wSolMint = "So11111111111111111111111111111111111111112"
private let jitoSolMint = "J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn"

/// Real account lists of the source transactions (index -> role in trailing comments).
private let kaminoAccounts = [
    "8jHdMjmzPWXZVA4fVu8JkdzsWzmDVbXhAGpF2QW7HXMd", // 0 owner
    "D6q6wuQSrifJKZYpR1M8R4YawnLDtDsMmWM1NbBmgJ59", // 1 reserve
    "7u3HeHxYDLhnCoErrtycNokbQYbWGzLs6JSDqGAv5PfF", // 2 lendingMarket
    "9DrvZvyWh1HuAoZxvYWMvkf2XCzryCpGgHqrMjyDWpmo", // 3 lendingMarketAuthority (mint authority)
    usdcMint, // 4 reserveLiquidityMint (USDC)
    "Bgq7trRgVMeq33yt235zM2onQ4bRDBsY5EWiTetF4qw6", // 5 reserveLiquiditySupply
    "B8V6WVjPxW1UGwVDfxH2d2r8SyT4cqn7dQRK6XneVa7D", // 6 reserveCollateralMint (cToken)
    "Gc9shR3rXpxb1qNW1TFWpgfDs7f8DMBahTEYQSt6UA8p", // 7 userSourceLiquidity
    "6fg7VUU2Qc4pgggoPzR6wWF7rQMcSoXcKZZFf7gb5pUn", // 8 userDestinationCollateral
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", // 9 collateralTokenProgram
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", // 10 liquidityTokenProgram
    "Sysvar1nstructions1111111111111111111111111" // 11 instructionSysvarAccount
]
private let stakePoolAccounts = [
    "Jito4APyf642JPZPx3hGc6WWJ8zPKtRbRs4P815Awbb", // 0 stakePool
    "6iQKfEyhr3bZMotVkW6beNZz5CPAkiwvgV2CTje9pVSS", // 1 withdrawAuthority (mint authority)
    "BgKUXdS29YcHCFrPm5M8oLHiTzZaMDjsebggjoaQ6KFL", // 2 reserveStake
    "5euppnDqDcRLh2jpevSb8cq2XopU2qVPw5QfwwtVvM9r", // 3 lamportsFrom (depositor / vault)
    "tVM6AiMxMcTY2yddHXJAqw1ZhKa1ivk7j4BWvSPSkxa", // 4 poolTokensTo
    "8yoigZfzZ1nNaadumY9uPVD118225UYHTDpmjpr2nrSa", // 5 managerFee
    "tVM6AiMxMcTY2yddHXJAqw1ZhKa1ivk7j4BWvSPSkxa", // 6 referrerFee
    jitoSolMint, // 7 poolMint (JitoSOL)
    "11111111111111111111111111111111", // 8 systemProgram
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" // 9 tokenProgram
]
/// a_to_b=1 source tx: 3 token_owner_account_a (wSOL), 4 token_vault_a, 5 token_owner_account_b, 6 token_vault_b.
private let orcaAtoBAccounts = [
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
    "FkaLnX17cXZGyeu3kZGdHCNdFMJJzBrPPYVvd18B3MZp",
    "2TAgfogn8JRwwTnsGKUa6WUT5Xdv1iMEzfEDMor68X9C",
    "5yiGAF4CjscmQkUU3qz97BwXHQgvuirNuM39T4BeLF1R",
    "26NPUT2NWS8vbgdZuD4iMKXbypYb6SpZKvmi76ezaG35",
    "HpKp7UA2hp9kNXR8qK7GBBrbRVtuToh9aaYLEf6eECN",
    "AbPTQH3jPZUfZYfyPmMhEPvD2tMuWjcFsgVjMbMvdTZ6",
    "FEVxyTHueSrVLXrUcDt2oPnkD5uy4gNegjgo9MCgzncd",
    "9gMKz51hfNyQb8oAhXPY1zTia27Xy4zoRUDTPPXc6Ntw",
    "9gMKz51hfNyQb8oAhXPY1zTia27Xy4zoRUDTPPXc6Ntw",
    "BiRp97qbCnFgDTAi4T5mQ1NUomULJUDyMwaqVVW8j5jH"
]
/// a_to_b=0 source tx: 3 token_owner_account_a, 4 token_vault_a, 5 token_owner_account_b (USDC), 6 token_vault_b.
private let orcaBtoAAccounts = [
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
    "MfDuWeqSHEqTFVYZ7LoexgAK9dxk7cy4DFJWjWMGVWa",
    "HD8i7qr1hd9ida6sN71RbkLxbWcbvZS4NA5CY6vfcDpj",
    "5rewPFmWf7BrXsUfhV6LUvy9eyPegNDD13XjA5fJAPzs",
    "Fq5fc9Ed3XRTsupzKYi5fRXLFsukmzhN7iDxwU3qNsig",
    "8VYWdU14V78rcDepwmNt54bb1aam5qVUMUpEtW8oCn1E",
    "CxorLTDskqhd4kE72bU11NezCnvh5okaZBQTuQTCxyFC",
    "BgkoigdGvjeZECXY9BNtr5hvLjmDSGA6ZUFfgPHYhhu1",
    "5mHqN11HRYvFanAhbXqhYX6NSecbFYASshH2XeWku37q",
    "5ihu7p2j6QmWNnZKEiYhhYh584bzCdgrAiP8gtyiQH1",
    "HnSfHKPXC1nrtwgCBZtSzkzps9UMpARYGFEL2pHTAC62"
]
private let raydiumAccounts = [
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", // 0
    "GU3DAFuGKUXaBiacotME7H8NaEAf5ShbFdNVKgjSe8GW", // 1 amm
    "5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1", // 2 amm authority
    "E2zXXbGj4VN5y4xqbfpWr5jxkjJYSSwND8EHmj3Li6kx", // 3 amm open orders
    "EmFhbRFHmW8STmqrbNCdkoMoX3edTRxE6w4UjsvEX5vY", // 4 amm target orders
    "9tjSdeopPzZmJXB8tmuJcmoEy6xusQQ57nscfWvsxgpD", // 5 pool coin vault (wSOL)
    "EfuMkyxmdUTvViRNVF1jRiq3rGB6x4ZVSVXuVaABmuTN", // 6 pool pc vault
    "srmqPvymJeFKQ4zGQed1GFppgkRHL9kaELCbyksJtPX", // 7 serum program
    "87T6DeaP3KtQZiNVVeBu4uR1cCV7cH93cCNM1ZqT89NK", // 8 serum market
    "D4BWdyLKkW9DeJhjoQjbvSYUnBYVhm7KHRZgYG7c63WL", // 9 serum bids
    "HE6ak7ZLdLudoASmi6powcYdru6fe8czeLtVkGjgRA9Y", // 10 serum asks
    "3Cp98fe2qynyw33uuMvQorY4rBp4tEAm6VkTtnhFh6fU", // 11 serum event queue
    "AWENhQNy7BGeruGuJUZpTpzboLSkikUWM4ucCCHZDzzY", // 12 serum coin vault
    "F9BgkFVtrAqVVDZRDc5Dyr5Sw8mzByxw4c8wXYicfWSF", // 13 serum pc vault
    "EodovhRMKjrBC97US6uyNCXgCM5v2ypyjLkh4933Rki3", // 14 serum vault signer
    "CmXGxHpA9LEiD3XJzNYiNrdcw5YgNn9UvZjtpgjxTqfd", // 15 userSourceTokenAccount (wSOL)
    "CSeJGj8FhV6ssicN2FsYyicfeM3bqiA581FepGFeoQrK", // 16 userDestinationTokenAccount
    "GCRTQagCbXUbopeLLsWHkENFH3MYm9ApwrwTyS8af7b2" // 17 user owner
]

/// End-to-end golden fixtures for the four hand-authored tier-3 specs.
///
/// Each test decodes a spec's REAL mainnet instruction bytes through
/// `DecodeSpecInterpreter.interpret(...crossCheck:)` and asserts both the rendered
/// statement and the effect cross-check verdict. Simulations are reconstructed from
/// the real on-chain SPL/System transfers of the source transaction named in each
/// case and run through the production `AssetMovement.build`, so the fixture models
/// exactly what the relay's simulation would surface — no numbers are tuned to pass.
/// The spec sources are loaded from the committed `core/registry/specs/*.json`, so
/// drift between the spec files and these fixtures fails the test.
///
/// Asset representation (relay effect assembly): a cross-checked leg's `asset` carries
/// the MINT address. `transferChecked`/`mintTo`/`mintToChecked` name the mint as an
/// explicit account; for a non-checked SPL `transfer` the relay resolves the mint from
/// the source token account; a System transfer carries "SOL". All four specs therefore
/// canonicalize and Confirm. An Orca swap's input leg is bounded ABOVE by the stated
/// `amount` (a price-limited partial fill moves less), so its spec uses `amountAtMost`;
/// Raydium SwapBaseIn is full-input, so its input leg is `exact`.
struct DecodeRegistryGoldenFixtureTests {
    // MARK: - Helpers

    private func loadSpec(_ filename: String) throws -> DecodeSpec {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Squads
            .deletingLastPathComponent() // Modules
            .deletingLastPathComponent() // repo root
        let url = repoRoot.appendingPathComponent("core/registry/specs/\(filename)")
        return try JSONDecoder().decode(DecodeSpec.self, from: Data(contentsOf: url))
    }

    private func instruction(_ program: String, _ rawDataHex: String) -> SquadDecodedInstruction {
        SquadDecodedInstruction(program: program, kind: "raw", summary: "", rawDataHex: rawDataHex)
    }

    private func idlDocument(_ json: String) throws -> AnchorIDLDocument {
        try JSONDecoder().decode(AnchorIDLDocument.self, from: Data(json.utf8))
    }

    private func transferEffect(
        asset: String?, amount: String, source: String, destination: String
    ) -> RelayInspectionEffect {
        RelayInspectionEffect(
            kind: "token_transfer", summary: "Transfer \(amount)", program: "SPL Token",
            asset: asset, amount: amount, source: source, destination: destination
        )
    }

    private func orcaResolvedIDL(_ spec: DecodeSpec) throws -> ResolvedProgramIDL {
        let document = try idlDocument(#"""
        { "metadata": { "name": "whirlpool" }, "instructions": [
          { "name": "swap", "discriminator": [248,198,158,145,225,117,135,200], "args": [
            { "name": "amount", "type": "u64" },
            { "name": "other_amount_threshold", "type": "u64" },
            { "name": "sqrt_price_limit", "type": "u128" },
            { "name": "amount_specified_is_input", "type": "bool" },
            { "name": "a_to_b", "type": "bool" } ] } ] }
        """#)
        return ResolvedProgramIDL(
            document: document,
            provenance: .onChainIDL(idlName: "whirlpool", hash: spec.bindsIdlHash ?? "", slot: 434_121_979)
        )
    }

    // MARK: - Kamino Lending deposit (bind-idl, unconditional) -> Confirmed

    //
    // Source tx: 3tDJBKDLQAYHa8nzmx6oB8c9BwcLHfLD5ELwQ7Xt4BW5Qmwry3QZkjoC9953A3yGNMo4fYPZ1R5NqLBVkydD9hVB
    // (slot 434121752). Discriminator a9c91e7e06cd6644; liquidityAmount = 192273. The
    // reserve-liquidity leg is a transferChecked of USDC (0.192272, one base unit below the
    // requested amount from Kamino's exchange-rate rounding — absorbed by the tolerance).

    @Test func kaminoDepositConfirmsAgainstSimulation() throws {
        let spec = try loadSpec("kamino-deposit.json")
        let document = try idlDocument(#"""
        { "metadata": { "name": "kamino_lending" }, "instructions": [
          { "name": "depositReserveLiquidity",
            "discriminator": [169,201,30,126,6,205,102,68],
            "args": [ { "name": "liquidityAmount", "type": "u64" } ] } ] }
        """#)
        let resolved = ResolvedProgramIDL(
            document: document,
            provenance: .onChainIDL(idlName: "kamino_lending", hash: spec.bindsIdlHash ?? "", slot: 434_121_752)
        )
        let userSource = kaminoAccounts[7]
        let effects = [
            transferEffect(asset: usdcMint, amount: "0.192272", source: userSource, destination: kaminoAccounts[5]),
            RelayInspectionEffect(
                kind: "token_mint", summary: "Mint 161277 base units", program: "SPL Token",
                asset: kaminoAccounts[6], amount: "161277 base units",
                source: kaminoAccounts[3], destination: kaminoAccounts[8]
            )
        ]
        let simulated = AssetMovement.build(from: effects, ownAccounts: [userSource, kaminoAccounts[8]])
        let context = CrossCheckContext(
            simulated: simulated,
            resolvedMints: [userSource: ResolvedMint(mint: usdcMint, decimals: 6, symbol: "USDC")]
        )
        let display = DecodeSpecInterpreter().interpret(
            instruction(kaminoProgram, "a9c91e7e06cd664411ef020000000000"),
            spec: spec, resolvedIDL: resolved, accounts: kaminoAccounts,
            mints: [userSource: MintInfo(symbol: "USDC", decimals: 6)], crossCheck: context
        )
        #expect(display?.summary == "Deposit 0.192273 USDC into Kamino")
        #expect(display?.crossCheck == .confirmed)
    }

    // MARK: - SPL Stake Pool DepositSol (standalone) -> Confirmed

    //
    // Source tx: JFWD8Z2JUxy1XkcGJiAGA42pV2KUPTBRfuZKc4s4XhxjDLpx3uFFA6NR6MnbQrNnAaRuiTmYG1sehj1fJ1ZbiHK
    // (slot 434120760). Tag [14], lamports = 50 SOL. SOL outflow is a System transfer; the
    // pool token (JitoSOL) inflow is a mintTo carrying the pool mint.

    @Test func stakePoolDepositSolConfirmsAgainstSimulation() throws {
        let spec = try loadSpec("stakepool-depositsol.json")
        let vault = stakePoolAccounts[3]
        let effects = [
            RelayInspectionEffect(
                kind: "sol_transfer", summary: "Transfer 50 SOL", program: "System Program",
                asset: "SOL", amount: "50 SOL", source: vault, destination: stakePoolAccounts[2]
            ),
            RelayInspectionEffect(
                kind: "token_mint", summary: "Mint 38721741063 base units", program: "SPL Token",
                asset: jitoSolMint, amount: "38721741063 base units",
                source: stakePoolAccounts[1], destination: stakePoolAccounts[4]
            )
        ]
        let simulated = AssetMovement.build(from: effects, ownAccounts: [vault, stakePoolAccounts[4]])
        let context = CrossCheckContext(
            simulated: simulated,
            resolvedMints: [jitoSolMint: ResolvedMint(mint: jitoSolMint, decimals: 9, symbol: "JitoSOL")]
        )
        let display = DecodeSpecInterpreter().interpret(
            instruction(stakePoolProgram, "0e00743ba40b000000"),
            spec: spec, resolvedIDL: nil, accounts: stakePoolAccounts,
            mints: [jitoSolMint: MintInfo(symbol: "JitoSOL", decimals: 9)], crossCheck: context
        )
        #expect(display?.summary == "Stake 50 SOL into the pool for JitoSOL")
        #expect(display?.crossCheck == .confirmed)
    }

    // MARK: - Orca Whirlpool swap (bind-idl, conditional on a_to_b) -> Confirmed

    //
    // Models the relay output once it resolves the mint of non-checked SPL transfer legs. The
    // simulated leg amounts are the relay's trimmed-decimal display (raw / 10^decimals, like a
    // checked transfer) of the real on-chain transfers; the input leg is a partial fill below the
    // stated cap (amountAtMost), the output leg clears the slippage floor (amountAtLeast).
    // Validate against a live relay capture at go-live.

    /// Source tx (a_to_b=1): 3bGpboJiB3wzbzXsaLt6s2rJ5WQpTmB5EqGLLyCNNCMA8oSotM8LWzRJ2AS5jcJ7Hi69DnMFtBTdowtT6DLsJQxq
    /// amount cap = 124309938021 (124.3 wSOL); real A-out = 6213910539 (~6.2 wSOL partial fill);
    /// real B-in = 89079866 = other_amount_threshold (the slippage floor).
    @Test func orcaSwapAtoBConfirmsAgainstSimulation() throws {
        let spec = try loadSpec("orca-swap.json")
        let accounts = orcaAtoBAccounts
        let tokenBMint = "A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS"
        let effects = [
            transferEffect(
                asset: wSolMint,
                amount: "6.213910539",
                source: accounts[3],
                destination: accounts[4]
            ),
            transferEffect(
                asset: tokenBMint,
                amount: "0.89079866",
                source: accounts[6],
                destination: accounts[5]
            )
        ]
        let simulated = AssetMovement.build(from: effects, ownAccounts: [accounts[3], accounts[5]])
        let context = CrossCheckContext(simulated: simulated, resolvedMints: [
            accounts[3]: ResolvedMint(mint: wSolMint, decimals: 9, symbol: "wSOL"),
            accounts[5]: ResolvedMint(mint: tokenBMint, decimals: 8, symbol: nil)
        ])
        let raw = "f8c69e91e17587c8651f73f11c0000003a404f0500000000fc86183d664fab1e00000000000000000101"
        let display = try DecodeSpecInterpreter().interpret(
            instruction(orcaProgram, raw), spec: spec, resolvedIDL: orcaResolvedIDL(spec),
            accounts: accounts, mints: [accounts[3]: MintInfo(symbol: "wSOL", decimals: 9)], crossCheck: context
        )
        #expect(display?.summary == "Swap 124.309938021 wSOL on Orca Whirlpool (A→B)")
        #expect(display?.crossCheck == .confirmed)
    }

    /// Source tx (a_to_b=0): 1wuXW17rHChZTKn5uFjKctxEgDz7hnmfBDXAWUWnABM4reMrUioy4CWEVXQ5xufwgN8gbzabndvCZG5x6jpM765
    /// amount cap = 294448763 (294.4 USDC); real B-out = 99012546 (partial fill); real A-in =
    /// 27076855 >= other_amount_threshold 16104804 (the slippage floor).
    @Test func orcaSwapBtoAConfirmsAgainstSimulation() throws {
        let spec = try loadSpec("orca-swap.json")
        let accounts = orcaBtoAAccounts
        let tokenAMint = "27G8MtK7VtTcCHkpASjSDdkWWYfoqT6ggEuKidVJidD4"
        let effects = [
            transferEffect(
                asset: usdcMint,
                amount: "99.012546",
                source: accounts[5],
                destination: accounts[6]
            ),
            transferEffect(
                asset: tokenAMint,
                amount: "27.076855",
                source: accounts[4],
                destination: accounts[3]
            )
        ]
        let simulated = AssetMovement.build(from: effects, ownAccounts: [accounts[5], accounts[3]])
        let context = CrossCheckContext(simulated: simulated, resolvedMints: [
            accounts[5]: ResolvedMint(mint: usdcMint, decimals: 6, symbol: "USDC"),
            accounts[3]: ResolvedMint(mint: tokenAMint, decimals: 6, symbol: nil)
        ])
        let raw = "f8c69e91e17587c87bee8c110000000064bdf500000000001ffa6dbbae246be901000000000000000100"
        let display = try DecodeSpecInterpreter().interpret(
            instruction(orcaProgram, raw), spec: spec, resolvedIDL: orcaResolvedIDL(spec),
            accounts: accounts, mints: [accounts[5]: MintInfo(symbol: "USDC", decimals: 6)], crossCheck: context
        )
        #expect(display?.summary == "Swap 294.448763 USDC on Orca Whirlpool (B→A)")
        #expect(display?.crossCheck == .confirmed)
    }

    /// Exact-output swap (amount_specified_is_input=0): `amount` is the OUTPUT quantity, so the
    /// amount-is-input variants must NOT apply. Reuses the a_to_b=1 bytes with the
    /// amount_specified_is_input byte (offset 40) flipped to 0. Every variant is gated on
    /// arg(amount_specified_is_input), so none matches and interpret returns nil — a clean
    /// fall-through to the generic decoder rather than a wrong statement.
    @Test func orcaExactOutputSwapFallsThroughInsteadOfMislabeling() throws {
        let spec = try loadSpec("orca-swap.json")
        let raw = "f8c69e91e17587c8651f73f11c0000003a404f0500000000fc86183d664fab1e00000000000000000001"
        let display = try DecodeSpecInterpreter().interpret(
            instruction(orcaProgram, raw), spec: spec, resolvedIDL: orcaResolvedIDL(spec),
            accounts: orcaAtoBAccounts,
            mints: [orcaAtoBAccounts[3]: MintInfo(symbol: "wSOL", decimals: 9)], crossCheck: nil
        )
        #expect(display == nil)
    }

    // MARK: - Raydium AMM v4 SwapBaseIn (standalone) -> Confirmed

    //
    // Source tx: 5q5CJB8HfisCqyFJ3ZAQ5X6xyRW67sgDVV95K3fT3178f8espXbSdeCrNh2atc94B2fX6vzNphuc5nNU3z34YcxP
    // (slot 434120378). Tag 9, amountIn = 258214310 (== the inner input transfer, exact); real
    // output = 1291513147091 >= minimumAmountOut 1278598020562 (the slippage floor). Models the
    // relay output once it resolves the mint of the non-checked SPL transfer legs; the simulated
    // leg amounts are the relay's trimmed-decimal display (raw / 10^decimals).

    @Test func raydiumSwapConfirmsAgainstSimulation() throws {
        let spec = try loadSpec("raydium-swap.json")
        let tokenOutMint = "7eYh6YK6f1dMjiQrwnUYgq8jQkpFYi8JdfPZLkHdpump"
        let effects = [
            transferEffect(
                asset: wSolMint, amount: "0.25821431",
                source: raydiumAccounts[15], destination: raydiumAccounts[5]
            ),
            transferEffect(
                asset: tokenOutMint, amount: "1291513.147091",
                source: raydiumAccounts[6], destination: raydiumAccounts[16]
            )
        ]
        let simulated = AssetMovement.build(from: effects, ownAccounts: [raydiumAccounts[15], raydiumAccounts[16]])
        let context = CrossCheckContext(simulated: simulated, resolvedMints: [
            raydiumAccounts[15]: ResolvedMint(mint: wSolMint, decimals: 9, symbol: "wSOL"),
            raydiumAccounts[16]: ResolvedMint(mint: tokenOutMint, decimals: 6, symbol: nil)
        ])
        let display = DecodeSpecInterpreter().interpret(
            instruction(raydiumProgram, "09a609640f00000000d27d61b229010000"),
            spec: spec, resolvedIDL: nil, accounts: raydiumAccounts,
            mints: [raydiumAccounts[15]: MintInfo(symbol: "wSOL", decimals: 9)], crossCheck: context
        )
        #expect(display?.summary == "Swap 0.25821431 wSOL on Raydium")
        #expect(display?.crossCheck == .confirmed)
    }
}
