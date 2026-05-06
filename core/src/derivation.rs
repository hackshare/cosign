//! SLIP-0010 hardened-only Ed25519 derivation.
//!
//! Reference: <https://github.com/satoshilabs/slips/blob/master/slip-0010.md>
//!
//! Ed25519 in SLIP-0010 supports HARDENED derivation only. Path components
//! must always have the high bit set (>= 0x80000000). This module enforces
//! that constraint.

use hmac::{Hmac, Mac};
use sha2::Sha512;
use zeroize::Zeroize;

type HmacSha512 = Hmac<Sha512>;

const HARDENED_OFFSET: u32 = 0x8000_0000;

#[derive(Debug, thiserror::Error)]
pub enum DerivationError {
    #[error("path component is not hardened (must be >= 0x80000000)")]
    NonHardenedComponent,
}

pub struct Path(pub Vec<u32>);

impl Path {
    /// Solana's BIP44 path: `m/44'/501'/0'/0'`. Matches Phantom and Solflare.
    pub fn solana_default() -> Self {
        Self(vec![
            44 | HARDENED_OFFSET,
            501 | HARDENED_OFFSET,
            HARDENED_OFFSET,
            HARDENED_OFFSET,
        ])
    }
}

/// Derive an Ed25519 master seed (32 bytes) from a BIP39 seed by walking the path.
pub fn derive(master_seed: &[u8], path: &Path) -> Result<[u8; 32], DerivationError> {
    let mut mac = HmacSha512::new_from_slice(b"ed25519 seed").expect("hmac key length");
    mac.update(master_seed);
    let mut hk = mac.finalize().into_bytes();

    let mut sk = [0u8; 32];
    let mut chain = [0u8; 32];
    sk.copy_from_slice(&hk[..32]);
    chain.copy_from_slice(&hk[32..]);
    hk.zeroize();

    for &index in &path.0 {
        if index < HARDENED_OFFSET {
            return Err(DerivationError::NonHardenedComponent);
        }
        let mut data = Vec::with_capacity(1 + 32 + 4);
        data.push(0x00);
        data.extend_from_slice(&sk);
        data.extend_from_slice(&index.to_be_bytes());

        let mut mac = HmacSha512::new_from_slice(&chain).expect("hmac key length");
        mac.update(&data);
        let mut h = mac.finalize().into_bytes();
        sk.copy_from_slice(&h[..32]);
        chain.copy_from_slice(&h[32..]);
        h.zeroize();
        data.zeroize();
    }

    chain.zeroize();
    Ok(sk)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// SLIP-0010 official test vector 1, root key (no derivation).
    /// Master seed: 000102030405060708090a0b0c0d0e0f
    #[test]
    fn slip10_vector_1_root() {
        let master_seed = hex::decode("000102030405060708090a0b0c0d0e0f").unwrap();
        let sk = derive(&master_seed, &Path(vec![])).unwrap();
        let expected = "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7";
        assert_eq!(hex::encode(sk), expected);
    }

    /// SLIP-0010 official test vector 1, m/0'.
    #[test]
    fn slip10_vector_1_m_0h() {
        let master_seed = hex::decode("000102030405060708090a0b0c0d0e0f").unwrap();
        let sk = derive(&master_seed, &Path(vec![HARDENED_OFFSET])).unwrap();
        let expected = "68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3";
        assert_eq!(hex::encode(sk), expected);
    }

    /// SLIP-0010 official test vector 1, m/0'/1'.
    #[test]
    fn slip10_vector_1_m_0h_1h() {
        let master_seed = hex::decode("000102030405060708090a0b0c0d0e0f").unwrap();
        let sk = derive(
            &master_seed,
            &Path(vec![HARDENED_OFFSET, 1 | HARDENED_OFFSET]),
        )
        .unwrap();
        let expected = "b1d0bad404bf35da785a64ca1ac54b2617211d2777696fbffaf208f746ae84f2";
        assert_eq!(hex::encode(sk), expected);
    }

    #[test]
    fn rejects_non_hardened_component() {
        let master_seed = vec![0u8; 64];
        let path = Path(vec![44]);
        assert!(matches!(
            derive(&master_seed, &path),
            Err(DerivationError::NonHardenedComponent)
        ));
    }

    #[test]
    fn solana_default_path_components() {
        let p = Path::solana_default();
        assert_eq!(
            p.0,
            vec![
                44 | HARDENED_OFFSET,
                501 | HARDENED_OFFSET,
                HARDENED_OFFSET,
                HARDENED_OFFSET,
            ]
        );
    }
}
