use bip39::{Language, Mnemonic};
use rand::RngCore;

#[derive(Debug, thiserror::Error)]
pub enum MnemonicError {
    #[error("word count must be 12 or 24")]
    InvalidWordCount,
    #[error("invalid mnemonic: {0}")]
    InvalidMnemonic(String),
}

pub fn generate(word_count: u8) -> Result<String, MnemonicError> {
    let entropy_bytes = match word_count {
        12 => 16,
        24 => 32,
        _ => return Err(MnemonicError::InvalidWordCount),
    };
    let mut entropy = vec![0u8; entropy_bytes];
    rand::thread_rng().fill_bytes(&mut entropy);
    Mnemonic::from_entropy(&entropy)
        .map(|m| m.to_string())
        .map_err(|e| MnemonicError::InvalidMnemonic(e.to_string()))
}

pub fn to_seed(mnemonic: &str, passphrase: &str) -> Result<[u8; 64], MnemonicError> {
    let m = Mnemonic::parse_in_normalized(Language::English, mnemonic)
        .map_err(|e| MnemonicError::InvalidMnemonic(e.to_string()))?;
    Ok(m.to_seed_normalized(passphrase))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_24_words() {
        let m = generate(24).unwrap();
        assert_eq!(m.split_whitespace().count(), 24);
    }

    #[test]
    fn generate_12_words() {
        let m = generate(12).unwrap();
        assert_eq!(m.split_whitespace().count(), 12);
    }

    #[test]
    fn generate_rejects_bad_word_count() {
        assert!(matches!(generate(15), Err(MnemonicError::InvalidWordCount)));
    }

    #[test]
    fn to_seed_rejects_invalid_mnemonic() {
        assert!(to_seed("not a real mnemonic at all", "").is_err());
    }

    #[test]
    fn trezor_test_vector_no_passphrase() {
        let mnemonic = "abandon abandon abandon abandon abandon abandon \
                        abandon abandon abandon abandon abandon about";
        let seed = to_seed(mnemonic, "").unwrap();
        let expected = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1\
                        9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4";
        assert_eq!(hex::encode(seed), expected);
    }

    #[test]
    fn trezor_test_vector_with_passphrase() {
        let mnemonic = "abandon abandon abandon abandon abandon abandon \
                        abandon abandon abandon abandon abandon about";
        let seed = to_seed(mnemonic, "TREZOR").unwrap();
        let expected = "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531\
                        f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04";
        assert_eq!(hex::encode(seed), expected);
    }
}
