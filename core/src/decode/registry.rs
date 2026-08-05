//! Signed decode-spec registry bundle: the model + Ed25519 verifier for the
//! relay-served spec bundle. Field-for-field port of
//! `Modules/Indexer/Sources/DecodeRegistryBundle.swift` and
//! `Modules/Squads/Sources/DecodeRegistryVerifier.swift`.

use base64::{Engine, engine::general_purpose::STANDARD as BASE64_STANDARD};
use serde::Deserialize;

use super::spec::DecodeSpec;
use super::wire::DecodeRegistryResponse;
use crate::keypair;
use solana_sdk::pubkey::Pubkey;

/// A signed bundle of decode specs, as served by the relay's decode-registry
/// endpoint. Parses only the bytes `DecodeRegistryVerifier` has already
/// authenticated — see [`verify_registry`].
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DecodeRegistryBundle {
    pub schema: i64,
    pub key_id: String,
    pub specs: Vec<DecodeSpec>,
}

/// Pinned root keys that sign the trusted-keys manifest, keyed by `keyId`,
/// base64-encoded 32-byte raw public keys. A manifest verifies only if it is
/// signed by one of these roots; anything else fails as an unknown root, so no
/// publisher keys are trusted and the registry stays inert (zero specs) rather
/// than trusting an unsigned or unpinned bundle. Rotate with overlap: ship the
/// new root alongside the old, cut signing over, then drop the old.
pub const DECODE_REGISTRY_ROOT_KEYS: &[(&str, &str)] = &[(
    "cosign-root-2026",
    "cAIqPHZiqqhH2J39lh3mwViCrt85PUdRdN9/lT8DxJs=",
)];

#[derive(Debug, PartialEq, Eq, thiserror::Error)]
pub enum DecodeRegistryVerificationError {
    #[error("registry signature is not valid base64")]
    InvalidSignatureEncoding,
    #[error("registry bundle keyId is not a known signing key")]
    UnknownKey,
    #[error("registry bundle signature does not verify")]
    InvalidSignature,
    #[error("registry bundle is not valid JSON")]
    MalformedBundle,
}

/// Verifies a signed decode-registry bundle: the signature must decode as
/// base64, the bundle bytes must parse as JSON, the bundle's `keyId` must be
/// a known public key, and the Ed25519 signature must verify over the
/// **exact** `response.bundle_data` bytes (untrimmed — a single appended
/// byte breaks verification). Order matters: a tampered-but-parseable
/// bundle signed with a known key fails at the signature check, not earlier.
pub fn verify_registry(
    response: &DecodeRegistryResponse,
    public_keys: &[(&str, &str)],
) -> Result<DecodeRegistryBundle, DecodeRegistryVerificationError> {
    let signature_bytes = BASE64_STANDARD
        .decode(response.signature_base64.trim())
        .map_err(|_| DecodeRegistryVerificationError::InvalidSignatureEncoding)?;
    let signature: [u8; 64] = signature_bytes
        .try_into()
        .map_err(|_| DecodeRegistryVerificationError::InvalidSignatureEncoding)?;

    let bundle: DecodeRegistryBundle = serde_json::from_slice(&response.bundle_data)
        .map_err(|_| DecodeRegistryVerificationError::MalformedBundle)?;

    let public_key_base64 = public_keys
        .iter()
        .find(|(key_id, _)| *key_id == bundle.key_id)
        .map(|(_, key)| *key)
        .ok_or(DecodeRegistryVerificationError::UnknownKey)?;
    let public_key_bytes = BASE64_STANDARD
        .decode(public_key_base64)
        .map_err(|_| DecodeRegistryVerificationError::UnknownKey)?;
    let public_key = Pubkey::try_from(public_key_bytes.as_slice())
        .map_err(|_| DecodeRegistryVerificationError::UnknownKey)?;

    if !keypair::verify(&public_key, &response.bundle_data, &signature) {
        return Err(DecodeRegistryVerificationError::InvalidSignature);
    }

    Ok(bundle)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decode::wire::DecodeRegistryResponse;
    use crate::keypair;
    use base64::{Engine, engine::general_purpose::STANDARD};

    const MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    fn signed(key_id: &str, bundle_json: &str) -> (DecodeRegistryResponse, Vec<(String, String)>) {
        let kp = keypair::from_mnemonic(MNEMONIC, "").unwrap();
        let bundle = bundle_json.as_bytes().to_vec();
        let sig = keypair::sign(&kp.private_key, &bundle);
        let response = DecodeRegistryResponse {
            bundle_data: bundle,
            signature_base64: STANDARD.encode(sig),
        };
        let pk_b64 = STANDARD.encode(kp.public_key.to_bytes());
        (response, vec![(key_id.to_string(), pk_b64)])
    }
    fn as_refs(keys: &[(String, String)]) -> Vec<(&str, &str)> {
        keys.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect()
    }

    #[test]
    fn verifies_a_valid_bundle() {
        let (resp, keys) = signed("k1", r#"{"schema":1,"keyId":"k1","specs":[]}"#);
        let bundle = verify_registry(&resp, &as_refs(&keys)).unwrap();
        assert_eq!(bundle.key_id, "k1");
        assert!(bundle.specs.is_empty());
    }

    #[test]
    fn rejects_a_tampered_bundle() {
        let (mut resp, keys) = signed("k1", r#"{"schema":1,"keyId":"k1","specs":[]}"#);
        resp.bundle_data = r#"{"schema":2,"keyId":"k1","specs":[]}"#.as_bytes().to_vec();
        assert_eq!(
            verify_registry(&resp, &as_refs(&keys)),
            Err(DecodeRegistryVerificationError::InvalidSignature)
        );
    }

    #[test]
    fn rejects_an_unknown_key() {
        let (resp, _) = signed("k1", r#"{"schema":1,"keyId":"k1","specs":[]}"#);
        assert_eq!(
            verify_registry(&resp, &[]),
            Err(DecodeRegistryVerificationError::UnknownKey)
        );
    }

    #[test]
    fn rejects_a_malformed_bundle() {
        // The signature is irrelevant here: a malformed bundle must fail at
        // the parse step, before the (known, valid) key is even looked up.
        let (mut resp, keys) = signed("k1", r#"{"schema":1,"keyId":"k1","specs":[]}"#);
        resp.bundle_data = b"not json".to_vec();
        assert_eq!(
            verify_registry(&resp, &as_refs(&keys)),
            Err(DecodeRegistryVerificationError::MalformedBundle)
        );
    }

    #[test]
    fn rejects_invalid_signature_base64() {
        let (mut resp, keys) = signed("k1", r#"{"schema":1,"keyId":"k1","specs":[]}"#);
        resp.signature_base64 = "not-valid-base64!!!".to_string();
        assert_eq!(
            verify_registry(&resp, &as_refs(&keys)),
            Err(DecodeRegistryVerificationError::InvalidSignatureEncoding)
        );
    }

    #[test]
    fn appended_newline_breaks_verification() {
        let (mut resp, keys) = signed(
            "cosign-registry-2026",
            r#"{"schema":1,"keyId":"cosign-registry-2026","specs":[]}"#,
        );
        resp.bundle_data.push(b'\n');
        assert!(verify_registry(&resp, &as_refs(&keys)).is_err());
    }

    #[test]
    fn rejects_a_key_whose_base64_is_not_32_bytes() {
        let (resp, _) = signed("k1", r#"{"schema":1,"keyId":"k1","specs":[]}"#);
        let short_key = vec![("k1".to_string(), STANDARD.encode([0u8; 4]))];
        assert_eq!(
            verify_registry(&resp, &as_refs(&short_key)),
            Err(DecodeRegistryVerificationError::UnknownKey)
        );
    }

    #[test]
    fn pins_the_cosign_root() {
        let (key_id, pk_b64) = DECODE_REGISTRY_ROOT_KEYS[0];
        assert_eq!(key_id, "cosign-root-2026");
        assert_eq!(STANDARD.decode(pk_b64).unwrap().len(), 32);
    }
}
