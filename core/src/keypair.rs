//! Solana-compatible Ed25519 keypair generation and signing.

use solana_sdk::{
    pubkey::Pubkey,
    signature::Signature,
    signer::{Signer, keypair::keypair_from_seed},
};
use zeroize::Zeroize;

use crate::{derivation, mnemonic};

#[derive(Debug, thiserror::Error)]
pub enum KeyPairError {
    #[error("mnemonic error: {0}")]
    Mnemonic(#[from] mnemonic::MnemonicError),
    #[error("derivation error: {0}")]
    Derivation(#[from] derivation::DerivationError),
    #[error("keypair construction failed: {0}")]
    Construction(String),
}

pub struct KeyPair {
    pub public_key: Pubkey,
    pub private_key: [u8; 32],
}

impl Drop for KeyPair {
    fn drop(&mut self) {
        self.private_key.zeroize();
    }
}

/// Derive a Solana keypair from a BIP39 mnemonic via SLIP-0010.
pub fn from_mnemonic(mnemonic: &str, passphrase: &str) -> Result<KeyPair, KeyPairError> {
    let seed = mnemonic::to_seed(mnemonic, passphrase)?;
    let private = derivation::derive(&seed, &derivation::Path::solana_default())?;
    let kp = keypair_from_seed(&private).map_err(|e| KeyPairError::Construction(e.to_string()))?;
    Ok(KeyPair {
        public_key: kp.pubkey(),
        private_key: private,
    })
}

/// Sign a message with a 32-byte Ed25519 private key. Returns 64-byte signature.
pub fn sign(private_key: &[u8; 32], message: &[u8]) -> [u8; 64] {
    let kp = keypair_from_seed(private_key)
        .expect("a 32-byte seed always produces a valid Ed25519 keypair");
    let sig: Signature = kp.sign_message(message);
    sig.into()
}

/// Verify a 64-byte Ed25519 signature against a 32-byte public key and message.
pub fn verify(public_key: &Pubkey, message: &[u8], signature: &[u8; 64]) -> bool {
    let sig = Signature::from(*signature);
    sig.verify(public_key.as_ref(), message)
}

/// Construct a Pubkey from a 32-byte slice; returns None if not exactly 32 bytes.
pub fn pubkey_from_bytes(bytes: &[u8]) -> Option<Pubkey> {
    Pubkey::try_from(bytes).ok()
}

/// Construct a Pubkey from its canonical base58 representation.
pub fn pubkey_from_base58(s: &str) -> Option<Pubkey> {
    s.parse::<Pubkey>().ok()
}

/// Import a Solana keypair from the 64-byte array `solana-cli` writes to
/// `keypair.json`: a 32-byte secret seed followed by the 32-byte public key.
/// Errors if the length is wrong or the public key does not match the secret.
pub fn from_secret_bytes(bytes: &[u8]) -> Result<KeyPair, KeyPairError> {
    if bytes.len() != 64 {
        return Err(KeyPairError::Construction(format!(
            "expected 64 bytes, got {}",
            bytes.len()
        )));
    }
    let mut seed = [0u8; 32];
    seed.copy_from_slice(&bytes[..32]);
    let kp = keypair_from_seed(&seed).map_err(|e| {
        seed.zeroize();
        KeyPairError::Construction(e.to_string())
    })?;
    if kp.pubkey().to_bytes()[..] != bytes[32..] {
        seed.zeroize();
        return Err(KeyPairError::Construction(
            "public key does not match secret key".to_string(),
        ));
    }
    Ok(KeyPair {
        public_key: kp.pubkey(),
        private_key: seed,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const ABANDON_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon \
                                    abandon abandon abandon abandon abandon about";

    #[test]
    fn derives_pubkey_with_known_length() {
        let kp = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        assert_eq!(kp.public_key.to_bytes().len(), 32);
        assert_eq!(kp.private_key.len(), 32);
    }

    #[test]
    fn pubkey_is_deterministic() {
        let first = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        let second = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        assert_eq!(first.public_key, second.public_key);
    }

    #[test]
    fn different_passphrase_yields_different_pubkey() {
        let plain = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        let passphrased = from_mnemonic(ABANDON_MNEMONIC, "TREZOR").unwrap();
        assert_ne!(plain.public_key, passphrased.public_key);
    }

    #[test]
    fn sign_and_verify_round_trip() {
        let kp = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        let message = b"transfer 1 SOL to ABC123";
        let sig = sign(&kp.private_key, message);
        assert!(verify(&kp.public_key, message, &sig));
    }

    #[test]
    fn verify_rejects_tampered_message() {
        let kp = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        let sig = sign(&kp.private_key, b"original");
        assert!(!verify(&kp.public_key, b"tampered", &sig));
    }

    #[test]
    fn verify_rejects_wrong_pubkey() {
        let kp1 = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        let kp2 = from_mnemonic(
            "legal winner thank year wave sausage worth useful legal winner thank yellow",
            "",
        )
        .unwrap();
        let sig = sign(&kp1.private_key, b"msg");
        assert!(!verify(&kp2.public_key, b"msg", &sig));
    }

    #[test]
    fn pubkey_to_string_round_trip_via_parse() {
        let kp = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        let s = kp.public_key.to_string();
        let parsed = pubkey_from_base58(&s).unwrap();
        assert_eq!(parsed, kp.public_key);
    }

    #[test]
    fn pubkey_to_string_length_in_solana_range() {
        let kp = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        let s = kp.public_key.to_string();
        assert!(
            (32..=44).contains(&s.len()),
            "Solana base58 addresses are 32-44 chars"
        );
    }

    #[test]
    fn from_secret_bytes_round_trips_a_keypair() {
        let kp = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        let mut bytes = Vec::with_capacity(64);
        bytes.extend_from_slice(&kp.private_key);
        bytes.extend_from_slice(&kp.public_key.to_bytes());
        let imported = from_secret_bytes(&bytes).unwrap();
        assert_eq!(imported.public_key, kp.public_key);
        assert_eq!(imported.private_key, kp.private_key);
    }

    #[test]
    fn from_secret_bytes_rejects_wrong_length() {
        assert!(from_secret_bytes(&[0u8; 32]).is_err());
        assert!(from_secret_bytes(&[0u8; 65]).is_err());
        assert!(from_secret_bytes(&[]).is_err());
    }

    #[test]
    fn from_secret_bytes_rejects_mismatched_public_key() {
        let kp = from_mnemonic(ABANDON_MNEMONIC, "").unwrap();
        let mut bytes = Vec::with_capacity(64);
        bytes.extend_from_slice(&kp.private_key);
        bytes.extend_from_slice(&[0u8; 32]);
        assert!(from_secret_bytes(&bytes).is_err());
    }
}
