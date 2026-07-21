//! SPL mint/token-account classification and the mint-metadata wire model
//! used to label decoded instruction amounts. `parse_spl_account` is a
//! verbatim port of the relay's own account-data classifier
//! (`relay-server.rs::parse_spl_account`); `ResolvedMint` and
//! `MintMetadataResponse` mirror `MintResolver.swift` and
//! `RelayModels+MintMetadata.swift`.

use solana_sdk::pubkey::Pubkey;

/// The result of classifying raw SPL account data by length (and, for
/// Token-2022 extended accounts, an `AccountType` byte).
#[derive(Debug, PartialEq, Eq)]
pub enum SplAccount {
    Mint { decimals: u8 },
    TokenAccount { mint: Pubkey },
}

/// Classifies raw account data as an SPL Mint (82 bytes; decimals at offset
/// 44) or SPL Token Account (165 bytes; mint at bytes 0..32). Token-2022
/// base layouts share these sizes; extended accounts (len > 165) carry an
/// AccountType byte at offset 165 (1 = Mint, 2 = Account). Anything else
/// fails safe to `None`.
pub fn parse_spl_account(data: &[u8]) -> Option<SplAccount> {
    match data.len() {
        82 => Some(SplAccount::Mint { decimals: data[44] }),
        165 => Some(SplAccount::TokenAccount {
            mint: Pubkey::try_from(&data[0..32]).ok()?,
        }),
        len if len > 165 => match data[165] {
            1 => Some(SplAccount::Mint { decimals: data[44] }),
            2 => Some(SplAccount::TokenAccount {
                mint: Pubkey::try_from(&data[0..32]).ok()?,
            }),
            _ => None,
        },
        _ => None,
    }
}

/// A mint resolved for display: its address, decimal precision, and (if
/// recognized) a human-readable symbol. Port of Swift's `ResolvedMint`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedMint {
    pub mint: String,
    pub decimals: i64,
    pub symbol: Option<String>,
}

/// Wire response from the relay's mint-metadata endpoint. Port of Swift's
/// `MintMetadataResponse`.
#[derive(Debug, Clone, PartialEq, Eq, serde::Deserialize)]
pub struct MintMetadataResponse {
    pub account: String,
    pub mint: String,
    pub decimals: i64,
    pub symbol: Option<String>,
}

const WELL_KNOWN_MINT_SYMBOLS: &[(&str, &str)] = &[
    ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "USDC"),
    ("Es9vMFrzaCERmJfrF4H2FYD4KConky11McCe8BenwNYB", "USDT"),
    ("J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn", "JitoSOL"),
    ("mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So", "mSOL"),
];

/// Looks up the display symbol for a well-known mint address. Unknown
/// mints return `None`.
pub fn well_known_mint_symbol(mint: &str) -> Option<&'static str> {
    WELL_KNOWN_MINT_SYMBOLS
        .iter()
        .find(|(address, _)| *address == mint)
        .map(|(_, symbol)| *symbol)
}

#[cfg(test)]
mod tests {
    use super::*;
    use solana_sdk::pubkey::Pubkey;

    #[test]
    fn parses_mint_by_length_82() {
        let mut data = vec![0u8; 82];
        data[44] = 6;
        assert_eq!(
            parse_spl_account(&data),
            Some(SplAccount::Mint { decimals: 6 })
        );
    }

    #[test]
    fn parses_token_account_by_length_165() {
        let mint = Pubkey::new_unique();
        let mut data = vec![0u8; 165];
        data[0..32].copy_from_slice(mint.as_ref());
        assert_eq!(
            parse_spl_account(&data),
            Some(SplAccount::TokenAccount { mint })
        );
    }

    #[test]
    fn parses_token_2022_extended_via_account_type_byte() {
        let mut mint_ext = vec![0u8; 200];
        mint_ext[44] = 9;
        mint_ext[165] = 1; // AccountType Mint
        assert_eq!(
            parse_spl_account(&mint_ext),
            Some(SplAccount::Mint { decimals: 9 })
        );

        let acct = Pubkey::new_unique();
        let mut acct_ext = vec![0u8; 200];
        acct_ext[0..32].copy_from_slice(acct.as_ref());
        acct_ext[165] = 2; // AccountType Account
        assert_eq!(
            parse_spl_account(&acct_ext),
            Some(SplAccount::TokenAccount { mint: acct })
        );
    }

    #[test]
    fn fails_safe_to_none_on_unrecognized_length_or_type() {
        assert_eq!(parse_spl_account(&[0u8; 100]), None);
        let mut bad = vec![0u8; 200];
        bad[165] = 7;
        assert_eq!(parse_spl_account(&bad), None);
    }

    #[test]
    fn fails_safe_to_none_on_short_or_empty_data() {
        assert_eq!(parse_spl_account(&[]), None);
        assert_eq!(parse_spl_account(&[0u8; 1]), None);
        assert_eq!(parse_spl_account(&[0u8; 44]), None);
    }

    #[test]
    fn well_known_symbols_and_response_parse() {
        assert_eq!(
            well_known_mint_symbol("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
            Some("USDC")
        );
        assert_eq!(well_known_mint_symbol("unknown"), None);
        let r: MintMetadataResponse =
            serde_json::from_str(r#"{"account":"A","mint":"M","decimals":6,"symbol":"USDC"}"#)
                .unwrap();
        assert_eq!(r.decimals, 6);
        assert_eq!(r.symbol.as_deref(), Some("USDC"));
        let r2: MintMetadataResponse =
            serde_json::from_str(r#"{"account":"A","mint":"M","decimals":9,"symbol":null}"#)
                .unwrap();
        assert_eq!(r2.symbol, None);
    }
}
