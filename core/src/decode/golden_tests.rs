//! Golden-fixture acceptance gate: the migration's proof that the Rust
//! decode stack matches `DecodeRegistryGoldenFixtureTests.swift` byte for
//! byte. Each test decodes a spec's real mainnet instruction bytes through
//! [`interpret_spec`] and asserts both the rendered statement and the
//! effect cross-check verdict. Simulations are reconstructed from the real
//! on-chain SPL/System transfers of the source transaction named in each
//! case and run through the production [`AssetMovement::build`], so the
//! fixture models exactly what the relay's simulation would surface — no
//! numbers are tuned to pass. The spec sources are loaded from the
//! committed `registry/specs/*.json`, so drift between the spec files and
//! these fixtures fails the test.
//!
//! Asset representation (relay effect assembly): a cross-checked leg's
//! `asset` carries the MINT address. `transferChecked`/`mintTo`/
//! `mintToChecked` name the mint as an explicit account; for a non-checked
//! SPL `transfer` the relay resolves the mint from the source token
//! account; a System transfer carries "SOL". All four specs therefore
//! canonicalize and Confirm. An Orca swap's input leg is bounded ABOVE by
//! the stated `amount` (a price-limited partial fill moves less), so its
//! spec uses `amountAtMost`; Raydium SwapBaseIn is full-input, so its input
//! leg is `exact`.

use std::collections::{HashMap, HashSet};

use crate::decode::idl::{AnchorIdlDocument, ResolvedProgramIdl};
use crate::decode::mints::ResolvedMint;
use crate::decode::spec::{DecodeSpec, MintInfo, interpret_spec};
use crate::decode::wire::{AssetMovement, RelayInspectionEffect};
use crate::decode::{CrossCheckContext, CrossCheckVerdict, DecodeProvenance};
use crate::types::DecodedInstruction;

const KAMINO_PROGRAM: &str = "KLend2g3cP87fffoy8q1mQqGKjrxjC8boSyAYavgmjD";
const STAKE_POOL_PROGRAM: &str = "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy";
const ORCA_PROGRAM: &str = "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc";
const RAYDIUM_PROGRAM: &str = "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8";

const USDC_MINT: &str = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";
const WSOL_MINT: &str = "So11111111111111111111111111111111111111112";
const JITOSOL_MINT: &str = "J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn";

/// Real account list of the source transaction (index -> role in trailing comments).
const KAMINO_ACCOUNTS: [&str; 12] = [
    "8jHdMjmzPWXZVA4fVu8JkdzsWzmDVbXhAGpF2QW7HXMd", // 0 owner
    "D6q6wuQSrifJKZYpR1M8R4YawnLDtDsMmWM1NbBmgJ59", // 1 reserve
    "7u3HeHxYDLhnCoErrtycNokbQYbWGzLs6JSDqGAv5PfF", // 2 lendingMarket
    "9DrvZvyWh1HuAoZxvYWMvkf2XCzryCpGgHqrMjyDWpmo", // 3 lendingMarketAuthority (mint authority)
    USDC_MINT,                                      // 4 reserveLiquidityMint (USDC)
    "Bgq7trRgVMeq33yt235zM2onQ4bRDBsY5EWiTetF4qw6", // 5 reserveLiquiditySupply
    "B8V6WVjPxW1UGwVDfxH2d2r8SyT4cqn7dQRK6XneVa7D", // 6 reserveCollateralMint (cToken)
    "Gc9shR3rXpxb1qNW1TFWpgfDs7f8DMBahTEYQSt6UA8p", // 7 userSourceLiquidity
    "6fg7VUU2Qc4pgggoPzR6wWF7rQMcSoXcKZZFf7gb5pUn", // 8 userDestinationCollateral
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",  // 9 collateralTokenProgram
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",  // 10 liquidityTokenProgram
    "Sysvar1nstructions1111111111111111111111111",  // 11 instructionSysvarAccount
];

const STAKE_POOL_ACCOUNTS: [&str; 10] = [
    "Jito4APyf642JPZPx3hGc6WWJ8zPKtRbRs4P815Awbb", // 0 stakePool
    "6iQKfEyhr3bZMotVkW6beNZz5CPAkiwvgV2CTje9pVSS", // 1 withdrawAuthority (mint authority)
    "BgKUXdS29YcHCFrPm5M8oLHiTzZaMDjsebggjoaQ6KFL", // 2 reserveStake
    "5euppnDqDcRLh2jpevSb8cq2XopU2qVPw5QfwwtVvM9r", // 3 lamportsFrom (depositor / vault)
    "tVM6AiMxMcTY2yddHXJAqw1ZhKa1ivk7j4BWvSPSkxa", // 4 poolTokensTo
    "8yoigZfzZ1nNaadumY9uPVD118225UYHTDpmjpr2nrSa", // 5 managerFee
    "tVM6AiMxMcTY2yddHXJAqw1ZhKa1ivk7j4BWvSPSkxa", // 6 referrerFee
    JITOSOL_MINT,                                  // 7 poolMint (JitoSOL)
    "11111111111111111111111111111111",            // 8 systemProgram
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", // 9 tokenProgram
];

/// a_to_b=1 source tx: 3 token_owner_account_a (wSOL), 4 token_vault_a, 5 token_owner_account_b, 6 token_vault_b.
const ORCA_A_TO_B_ACCOUNTS: [&str; 11] = [
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
    "BiRp97qbCnFgDTAi4T5mQ1NUomULJUDyMwaqVVW8j5jH",
];

/// a_to_b=0 source tx: 3 token_owner_account_a, 4 token_vault_a, 5 token_owner_account_b (USDC), 6 token_vault_b.
const ORCA_B_TO_A_ACCOUNTS: [&str; 11] = [
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
    "HnSfHKPXC1nrtwgCBZtSzkzps9UMpARYGFEL2pHTAC62",
];

const RAYDIUM_ACCOUNTS: [&str; 18] = [
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",  // 0
    "GU3DAFuGKUXaBiacotME7H8NaEAf5ShbFdNVKgjSe8GW", // 1 amm
    "5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1", // 2 amm authority
    "E2zXXbGj4VN5y4xqbfpWr5jxkjJYSSwND8EHmj3Li6kx", // 3 amm open orders
    "EmFhbRFHmW8STmqrbNCdkoMoX3edTRxE6w4UjsvEX5vY", // 4 amm target orders
    "9tjSdeopPzZmJXB8tmuJcmoEy6xusQQ57nscfWvsxgpD", // 5 pool coin vault (wSOL)
    "EfuMkyxmdUTvViRNVF1jRiq3rGB6x4ZVSVXuVaABmuTN", // 6 pool pc vault
    "srmqPvymJeFKQ4zGQed1GFppgkRHL9kaELCbyksJtPX",  // 7 serum program
    "87T6DeaP3KtQZiNVVeBu4uR1cCV7cH93cCNM1ZqT89NK", // 8 serum market
    "D4BWdyLKkW9DeJhjoQjbvSYUnBYVhm7KHRZgYG7c63WL", // 9 serum bids
    "HE6ak7ZLdLudoASmi6powcYdru6fe8czeLtVkGjgRA9Y", // 10 serum asks
    "3Cp98fe2qynyw33uuMvQorY4rBp4tEAm6VkTtnhFh6fU", // 11 serum event queue
    "AWENhQNy7BGeruGuJUZpTpzboLSkikUWM4ucCCHZDzzY", // 12 serum coin vault
    "F9BgkFVtrAqVVDZRDc5Dyr5Sw8mzByxw4c8wXYicfWSF", // 13 serum pc vault
    "EodovhRMKjrBC97US6uyNCXgCM5v2ypyjLkh4933Rki3", // 14 serum vault signer
    "CmXGxHpA9LEiD3XJzNYiNrdcw5YgNn9UvZjtpgjxTqfd", // 15 userSourceTokenAccount (wSOL)
    "CSeJGj8FhV6ssicN2FsYyicfeM3bqiA581FepGFeoQrK", // 16 userDestinationTokenAccount
    "GCRTQagCbXUbopeLLsWHkENFH3MYm9ApwrwTyS8af7b2", // 17 user owner
];

fn accounts_vec(raw: &[&str]) -> Vec<String> {
    raw.iter().map(|value| value.to_string()).collect()
}

fn ix(program: &str, raw_data_hex: &str) -> DecodedInstruction {
    DecodedInstruction {
        program: program.into(),
        kind: "raw".into(),
        summary: String::new(),
        accounts: vec![],
        raw_data_hex: raw_data_hex.into(),
        config_action: None,
    }
}

/// Loads a spec from the committed `registry/specs/*.json` — the same
/// source of truth the production registry loader reads — so drift between
/// a spec file and this fixture fails the test rather than passing against
/// a stale copy.
fn load_spec(filename: &str) -> DecodeSpec {
    let path = format!("registry/specs/{filename}");
    let json =
        std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("read {path}: {error}"));
    serde_json::from_str(&json).unwrap_or_else(|error| panic!("parse {filename}: {error}"))
}

fn transfer_effect(
    asset: Option<&str>,
    amount: &str,
    source: &str,
    destination: &str,
) -> RelayInspectionEffect {
    RelayInspectionEffect {
        kind: "token_transfer".into(),
        summary: format!("Transfer {amount}"),
        program: Some("SPL Token".into()),
        asset: asset.map(String::from),
        amount: Some(amount.into()),
        source: Some(source.into()),
        destination: Some(destination.into()),
    }
}

/// The inline Orca Whirlpool `swap` IDL used by both directional fixtures
/// and the exact-output fall-through case, bound with provenance pinned to
/// `spec.binds_idl_hash` at the real on-chain slot.
fn orca_resolved_idl(spec: &DecodeSpec) -> ResolvedProgramIdl {
    let document: AnchorIdlDocument = serde_json::from_str(
        r#"{ "metadata": { "name": "whirlpool" }, "instructions": [
          { "name": "swap", "discriminator": [248,198,158,145,225,117,135,200], "args": [
            { "name": "amount", "type": "u64" },
            { "name": "other_amount_threshold", "type": "u64" },
            { "name": "sqrt_price_limit", "type": "u128" },
            { "name": "amount_specified_is_input", "type": "bool" },
            { "name": "a_to_b", "type": "bool" } ] } ] }"#,
    )
    .unwrap();
    ResolvedProgramIdl {
        document,
        provenance: DecodeProvenance::OnChainIdl {
            idl_name: "whirlpool".into(),
            hash: spec.binds_idl_hash.clone().unwrap_or_default(),
            slot: 434_121_979,
        },
    }
}

// -- Kamino Lending deposit (bind-idl, unconditional) -> Confirmed --
//
// Source tx: 3tDJBKDLQAYHa8nzmx6oB8c9BwcLHfLD5ELwQ7Xt4BW5Qmwry3QZkjoC9953A3yGNMo4fYPZ1R5NqLBVkydD9hVB
// (slot 434121752). Discriminator a9c91e7e06cd6644; liquidityAmount = 192273. The
// reserve-liquidity leg is a transferChecked of USDC (0.192272, one base unit below the
// requested amount from Kamino's exchange-rate rounding — absorbed by the tolerance).

#[test]
fn kamino_deposit_confirms_against_simulation() {
    let spec = load_spec("kamino-deposit.json");
    let document: AnchorIdlDocument = serde_json::from_str(
        r#"{ "metadata": { "name": "kamino_lending" }, "instructions": [
          { "name": "depositReserveLiquidity",
            "discriminator": [169,201,30,126,6,205,102,68],
            "args": [ { "name": "liquidityAmount", "type": "u64" } ] } ] }"#,
    )
    .unwrap();
    let resolved = ResolvedProgramIdl {
        document,
        provenance: DecodeProvenance::OnChainIdl {
            idl_name: "kamino_lending".into(),
            hash: spec.binds_idl_hash.clone().unwrap_or_default(),
            slot: 434_121_752,
        },
    };
    let accounts = accounts_vec(&KAMINO_ACCOUNTS);
    let user_source = accounts[7].clone();
    let effects = vec![
        transfer_effect(Some(USDC_MINT), "0.192272", &user_source, &accounts[5]),
        RelayInspectionEffect {
            kind: "token_mint".into(),
            summary: "Mint 161277 base units".into(),
            program: Some("SPL Token".into()),
            asset: Some(accounts[6].clone()),
            amount: Some("161277 base units".into()),
            source: Some(accounts[3].clone()),
            destination: Some(accounts[8].clone()),
        },
    ];
    let own: HashSet<String> = [user_source.clone(), accounts[8].clone()]
        .into_iter()
        .collect();
    let simulated = AssetMovement::build(&effects, &own);
    let context = CrossCheckContext {
        simulated,
        resolved_mints: [(
            user_source.clone(),
            ResolvedMint {
                mint: USDC_MINT.into(),
                decimals: 6,
                symbol: Some("USDC".into()),
            },
        )]
        .into_iter()
        .collect(),
    };
    let mints: HashMap<String, MintInfo> = [(
        user_source.clone(),
        MintInfo {
            symbol: "USDC".into(),
            decimals: 6,
        },
    )]
    .into_iter()
    .collect();

    let display = interpret_spec(
        &ix(KAMINO_PROGRAM, "a9c91e7e06cd664411ef020000000000"),
        &spec,
        Some(&resolved),
        &accounts,
        &mints,
        Some(&context),
    )
    .unwrap();

    assert_eq!(display.summary, "Deposit 0.192273 USDC into Kamino");
    assert_eq!(display.cross_check, Some(CrossCheckVerdict::Confirmed));
}

// -- SPL Stake Pool DepositSol (standalone) -> Confirmed --
//
// Source tx: JFWD8Z2JUxy1XkcGJiAGA42pV2KUPTBRfuZKc4s4XhxjDLpx3uFFA6NR6MnbQrNnAaRuiTmYG1sehj1fJ1ZbiHK
// (slot 434120760). Tag [14], lamports = 50 SOL. SOL outflow is a System transfer; the
// pool token (JitoSOL) inflow is a mintTo carrying the pool mint.

#[test]
fn stakepool_depositsol_confirms_against_simulation() {
    let spec = load_spec("stakepool-depositsol.json");
    let accounts = accounts_vec(&STAKE_POOL_ACCOUNTS);
    let vault = accounts[3].clone();
    let effects = vec![
        RelayInspectionEffect {
            kind: "sol_transfer".into(),
            summary: "Transfer 50 SOL".into(),
            program: Some("System Program".into()),
            asset: Some("SOL".into()),
            amount: Some("50 SOL".into()),
            source: Some(vault.clone()),
            destination: Some(accounts[2].clone()),
        },
        RelayInspectionEffect {
            kind: "token_mint".into(),
            summary: "Mint 38721741063 base units".into(),
            program: Some("SPL Token".into()),
            asset: Some(JITOSOL_MINT.into()),
            amount: Some("38721741063 base units".into()),
            source: Some(accounts[1].clone()),
            destination: Some(accounts[4].clone()),
        },
    ];
    let own: HashSet<String> = [vault, accounts[4].clone()].into_iter().collect();
    let simulated = AssetMovement::build(&effects, &own);
    let context = CrossCheckContext {
        simulated,
        resolved_mints: [(
            JITOSOL_MINT.to_string(),
            ResolvedMint {
                mint: JITOSOL_MINT.into(),
                decimals: 9,
                symbol: Some("JitoSOL".into()),
            },
        )]
        .into_iter()
        .collect(),
    };
    let mints: HashMap<String, MintInfo> = [(
        JITOSOL_MINT.to_string(),
        MintInfo {
            symbol: "JitoSOL".into(),
            decimals: 9,
        },
    )]
    .into_iter()
    .collect();

    let display = interpret_spec(
        &ix(STAKE_POOL_PROGRAM, "0e00743ba40b000000"),
        &spec,
        None,
        &accounts,
        &mints,
        Some(&context),
    )
    .unwrap();

    assert_eq!(display.summary, "Stake 50 SOL into the pool for JitoSOL");
    assert_eq!(display.cross_check, Some(CrossCheckVerdict::Confirmed));
}

// -- Orca Whirlpool swap (bind-idl, conditional on a_to_b) -> Confirmed --
//
// Models the relay output once it resolves the mint of non-checked SPL transfer legs. The
// simulated leg amounts are the relay's trimmed-decimal display (raw / 10^decimals, like a
// checked transfer) of the real on-chain transfers; the input leg is a partial fill below the
// stated cap (amountAtMost), the output leg clears the slippage floor (amountAtLeast).

/// Source tx (a_to_b=1): 3bGpboJiB3wzbzXsaLt6s2rJ5WQpTmB5EqGLLyCNNCMA8oSotM8LWzRJ2AS5jcJ7Hi69DnMFtBTdowtT6DLsJQxq
/// amount cap = 124309938021 (124.3 wSOL); real A-out = 6213910539 (~6.2 wSOL partial fill);
/// real B-in = 89079866 = other_amount_threshold (the slippage floor).
#[test]
fn orca_swap_a_to_b_confirms_against_simulation() {
    let spec = load_spec("orca-swap.json");
    let accounts = accounts_vec(&ORCA_A_TO_B_ACCOUNTS);
    let token_b_mint = "A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS";
    let effects = vec![
        transfer_effect(Some(WSOL_MINT), "6.213910539", &accounts[3], &accounts[4]),
        transfer_effect(Some(token_b_mint), "0.89079866", &accounts[6], &accounts[5]),
    ];
    let own: HashSet<String> = [accounts[3].clone(), accounts[5].clone()]
        .into_iter()
        .collect();
    let simulated = AssetMovement::build(&effects, &own);
    let context = CrossCheckContext {
        simulated,
        resolved_mints: [
            (
                accounts[3].clone(),
                ResolvedMint {
                    mint: WSOL_MINT.into(),
                    decimals: 9,
                    symbol: Some("wSOL".into()),
                },
            ),
            (
                accounts[5].clone(),
                ResolvedMint {
                    mint: token_b_mint.into(),
                    decimals: 8,
                    symbol: None,
                },
            ),
        ]
        .into_iter()
        .collect(),
    };
    let mints: HashMap<String, MintInfo> = [(
        accounts[3].clone(),
        MintInfo {
            symbol: "wSOL".into(),
            decimals: 9,
        },
    )]
    .into_iter()
    .collect();
    let resolved = orca_resolved_idl(&spec);
    let raw =
        "f8c69e91e17587c8651f73f11c0000003a404f0500000000fc86183d664fab1e00000000000000000101";

    let display = interpret_spec(
        &ix(ORCA_PROGRAM, raw),
        &spec,
        Some(&resolved),
        &accounts,
        &mints,
        Some(&context),
    )
    .unwrap();

    assert_eq!(
        display.summary,
        "Swap 124.309938021 wSOL on Orca Whirlpool (A→B)"
    );
    assert_eq!(display.cross_check, Some(CrossCheckVerdict::Confirmed));
}

/// Source tx (a_to_b=0): 1wuXW17rHChZTKn5uFjKctxEgDz7hnmfBDXAWUWnABM4reMrUioy4CWEVXQ5xufwgN8gbzabndvCZG5x6jpM765
/// amount cap = 294448763 (294.4 USDC); real B-out = 99012546 (partial fill); real A-in =
/// 27076855 >= other_amount_threshold 16104804 (the slippage floor).
#[test]
fn orca_swap_b_to_a_confirms_against_simulation() {
    let spec = load_spec("orca-swap.json");
    let accounts = accounts_vec(&ORCA_B_TO_A_ACCOUNTS);
    let token_a_mint = "27G8MtK7VtTcCHkpASjSDdkWWYfoqT6ggEuKidVJidD4";
    let effects = vec![
        transfer_effect(Some(USDC_MINT), "99.012546", &accounts[5], &accounts[6]),
        transfer_effect(Some(token_a_mint), "27.076855", &accounts[4], &accounts[3]),
    ];
    let own: HashSet<String> = [accounts[5].clone(), accounts[3].clone()]
        .into_iter()
        .collect();
    let simulated = AssetMovement::build(&effects, &own);
    let context = CrossCheckContext {
        simulated,
        resolved_mints: [
            (
                accounts[5].clone(),
                ResolvedMint {
                    mint: USDC_MINT.into(),
                    decimals: 6,
                    symbol: Some("USDC".into()),
                },
            ),
            (
                accounts[3].clone(),
                ResolvedMint {
                    mint: token_a_mint.into(),
                    decimals: 6,
                    symbol: None,
                },
            ),
        ]
        .into_iter()
        .collect(),
    };
    let mints: HashMap<String, MintInfo> = [(
        accounts[5].clone(),
        MintInfo {
            symbol: "USDC".into(),
            decimals: 6,
        },
    )]
    .into_iter()
    .collect();
    let resolved = orca_resolved_idl(&spec);
    let raw =
        "f8c69e91e17587c87bee8c110000000064bdf500000000001ffa6dbbae246be901000000000000000100";

    let display = interpret_spec(
        &ix(ORCA_PROGRAM, raw),
        &spec,
        Some(&resolved),
        &accounts,
        &mints,
        Some(&context),
    )
    .unwrap();

    assert_eq!(
        display.summary,
        "Swap 294.448763 USDC on Orca Whirlpool (B→A)"
    );
    assert_eq!(display.cross_check, Some(CrossCheckVerdict::Confirmed));
}

/// Exact-output swap (amount_specified_is_input=0): `amount` is the OUTPUT quantity, so the
/// amount-is-input variants must NOT apply. Reuses the a_to_b=1 bytes with the
/// amount_specified_is_input byte (offset 40) flipped to 0. Every variant is gated on
/// arg(amount_specified_is_input), so none matches and interpret_spec returns `None` — a clean
/// fall-through to the generic decoder rather than a wrong statement.
#[test]
fn orca_exact_output_swap_falls_through_instead_of_mislabeling() {
    let spec = load_spec("orca-swap.json");
    let accounts = accounts_vec(&ORCA_A_TO_B_ACCOUNTS);
    let resolved = orca_resolved_idl(&spec);
    let mints: HashMap<String, MintInfo> = [(
        accounts[3].clone(),
        MintInfo {
            symbol: "wSOL".into(),
            decimals: 9,
        },
    )]
    .into_iter()
    .collect();
    let raw =
        "f8c69e91e17587c8651f73f11c0000003a404f0500000000fc86183d664fab1e00000000000000000001";

    let display = interpret_spec(
        &ix(ORCA_PROGRAM, raw),
        &spec,
        Some(&resolved),
        &accounts,
        &mints,
        None,
    );

    assert!(display.is_none());
}

// -- Raydium AMM v4 SwapBaseIn (standalone) -> Confirmed --
//
// Source tx: 5q5CJB8HfisCqyFJ3ZAQ5X6xyRW67sgDVV95K3fT3178f8espXbSdeCrNh2atc94B2fX6vzNphuc5nNU3z34YcxP
// (slot 434120378). Tag 9, amountIn = 258214310 (== the inner input transfer, exact); real
// output = 1291513147091 >= minimumAmountOut 1278598020562 (the slippage floor). Models the
// relay output once it resolves the mint of the non-checked SPL transfer legs; the simulated
// leg amounts are the relay's trimmed-decimal display (raw / 10^decimals).

#[test]
fn raydium_swap_confirms_against_simulation() {
    let spec = load_spec("raydium-swap.json");
    let accounts = accounts_vec(&RAYDIUM_ACCOUNTS);
    let token_out_mint = "7eYh6YK6f1dMjiQrwnUYgq8jQkpFYi8JdfPZLkHdpump";
    let effects = vec![
        transfer_effect(Some(WSOL_MINT), "0.25821431", &accounts[15], &accounts[5]),
        transfer_effect(
            Some(token_out_mint),
            "1291513.147091",
            &accounts[6],
            &accounts[16],
        ),
    ];
    let own: HashSet<String> = [accounts[15].clone(), accounts[16].clone()]
        .into_iter()
        .collect();
    let simulated = AssetMovement::build(&effects, &own);
    let context = CrossCheckContext {
        simulated,
        resolved_mints: [
            (
                accounts[15].clone(),
                ResolvedMint {
                    mint: WSOL_MINT.into(),
                    decimals: 9,
                    symbol: Some("wSOL".into()),
                },
            ),
            (
                accounts[16].clone(),
                ResolvedMint {
                    mint: token_out_mint.into(),
                    decimals: 6,
                    symbol: None,
                },
            ),
        ]
        .into_iter()
        .collect(),
    };
    let mints: HashMap<String, MintInfo> = [(
        accounts[15].clone(),
        MintInfo {
            symbol: "wSOL".into(),
            decimals: 9,
        },
    )]
    .into_iter()
    .collect();

    let display = interpret_spec(
        &ix(RAYDIUM_PROGRAM, "09a609640f00000000d27d61b229010000"),
        &spec,
        None,
        &accounts,
        &mints,
        Some(&context),
    )
    .unwrap();

    assert_eq!(display.summary, "Swap 0.25821431 wSOL on Raydium");
    assert_eq!(display.cross_check, Some(CrossCheckVerdict::Confirmed));
}
