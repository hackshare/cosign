//! The trusted-keys manifest: the root-signed list of decode-publisher keys
//! the app trusts to sign the registry bundle. Verified against the pinned
//! `DECODE_REGISTRY_ROOT_KEYS`; see `verify_manifest`.

use crate::keypair;
use base64::{Engine, engine::general_purpose::STANDARD};
use serde::Deserialize;
use solana_sdk::pubkey::Pubkey;

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrustedKeysManifest {
    pub schema: u32,
    pub issued_at: String,
    pub expires_at: String,
    pub root_key_id: String,
    pub publishers: Vec<PublisherKey>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublisherKey {
    pub key_id: String,
    pub public_key: String,
    #[serde(default)]
    pub status: Option<String>,
}

/// Parses the manifest JSON. Any malformed input yields `None` (fail-safe: a
/// manifest that won't parse contributes no trusted keys).
pub fn parse_manifest(bytes: &[u8]) -> Option<TrustedKeysManifest> {
    serde_json::from_slice(bytes).ok()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedManifest {
    pub issued_at: String,
    /// `(keyId, publicKeyBase64)` for each active publisher.
    pub publisher_keys: Vec<(String, String)>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ManifestVerificationError {
    InvalidSignatureEncoding,
    MalformedManifest,
    UnknownRoot,
    InvalidSignature,
    Expired,
    RolledBack,
}

/// Verifies the manifest against the pinned root keys and its freshness.
/// `now_rfc3339` and `last_accepted_issued_at` are UTC RFC3339 (`...Z`) strings
/// compared lexically. Returns the active publisher keys on success.
pub fn verify_manifest(
    manifest_bytes: &[u8],
    signature_base64: &str,
    root_keys: &[(&str, &str)],
    now_rfc3339: &str,
    last_accepted_issued_at: Option<&str>,
) -> Result<VerifiedManifest, ManifestVerificationError> {
    let sig_bytes = STANDARD
        .decode(signature_base64.trim())
        .map_err(|_| ManifestVerificationError::InvalidSignatureEncoding)?;
    let signature: [u8; 64] = sig_bytes
        .as_slice()
        .try_into()
        .map_err(|_| ManifestVerificationError::InvalidSignatureEncoding)?;

    let manifest =
        parse_manifest(manifest_bytes).ok_or(ManifestVerificationError::MalformedManifest)?;

    let root_pubkey_b64 = root_keys
        .iter()
        .find(|(id, _)| *id == manifest.root_key_id)
        .map(|(_, pk)| *pk)
        .ok_or(ManifestVerificationError::UnknownRoot)?;
    let root_bytes = STANDARD
        .decode(root_pubkey_b64)
        .map_err(|_| ManifestVerificationError::UnknownRoot)?;
    let root_pubkey = Pubkey::try_from(root_bytes.as_slice())
        .map_err(|_| ManifestVerificationError::UnknownRoot)?;

    if !keypair::verify(&root_pubkey, manifest_bytes, &signature) {
        return Err(ManifestVerificationError::InvalidSignature);
    }

    if now_rfc3339 > manifest.expires_at.as_str() {
        return Err(ManifestVerificationError::Expired);
    }
    if let Some(last) = last_accepted_issued_at
        && manifest.issued_at.as_str() < last
    {
        return Err(ManifestVerificationError::RolledBack);
    }

    let publisher_keys = manifest
        .publishers
        .into_iter()
        .filter(|p| p.status.as_deref().unwrap_or("active") == "active")
        .map(|p| (p.key_id, p.public_key))
        .collect();
    Ok(VerifiedManifest {
        issued_at: manifest.issued_at,
        publisher_keys,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keypair;
    use base64::{Engine, engine::general_purpose::STANDARD};

    const ROOT_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    fn signed(json: &str) -> (Vec<u8>, String, String) {
        // returns (manifest bytes, signature base64, root pubkey base64)
        let kp = keypair::from_mnemonic(ROOT_MNEMONIC, "").unwrap();
        let bytes = json.as_bytes().to_vec();
        let sig = keypair::sign(&kp.private_key, &bytes);
        (
            bytes,
            STANDARD.encode(sig),
            STANDARD.encode(kp.public_key.to_bytes()),
        )
    }

    fn manifest_json(issued: &str, expires: &str) -> String {
        format!(
            r#"{{"schema":1,"issuedAt":"{issued}","expiresAt":"{expires}",
      "rootKeyId":"root","publishers":[{{"keyId":"pub-1","publicKey":"UPUB","status":"active"}}]}}"#
        )
    }

    #[test]
    fn valid_current_manifest_yields_publisher_keys() {
        let (bytes, sig, pk) = signed(&manifest_json(
            "2026-08-01T00:00:00Z",
            "2026-08-15T00:00:00Z",
        ));
        let roots = [("root", pk.as_str())];
        let v = verify_manifest(&bytes, &sig, &roots, "2026-08-10T00:00:00Z", None).unwrap();
        assert_eq!(v.issued_at, "2026-08-01T00:00:00Z");
        assert_eq!(
            v.publisher_keys,
            vec![("pub-1".to_string(), "UPUB".to_string())]
        );
    }

    #[test]
    fn expired_manifest_is_rejected() {
        let (bytes, sig, pk) = signed(&manifest_json(
            "2026-08-01T00:00:00Z",
            "2026-08-15T00:00:00Z",
        ));
        let roots = [("root", pk.as_str())];
        let r = verify_manifest(&bytes, &sig, &roots, "2026-08-20T00:00:00Z", None);
        assert_eq!(r, Err(ManifestVerificationError::Expired));
    }

    #[test]
    fn rolled_back_manifest_is_rejected() {
        let (bytes, sig, pk) = signed(&manifest_json(
            "2026-08-01T00:00:00Z",
            "2026-08-15T00:00:00Z",
        ));
        let roots = [("root", pk.as_str())];
        let r = verify_manifest(
            &bytes,
            &sig,
            &roots,
            "2026-08-10T00:00:00Z",
            Some("2026-08-05T00:00:00Z"),
        );
        assert_eq!(r, Err(ManifestVerificationError::RolledBack));
    }

    #[test]
    fn same_or_newer_issued_at_is_accepted() {
        let (bytes, sig, pk) = signed(&manifest_json(
            "2026-08-10T00:00:00Z",
            "2026-08-24T00:00:00Z",
        ));
        let roots = [("root", pk.as_str())];
        assert!(
            verify_manifest(
                &bytes,
                &sig,
                &roots,
                "2026-08-11T00:00:00Z",
                Some("2026-08-10T00:00:00Z")
            )
            .is_ok()
        );
    }

    #[test]
    fn unknown_root_key_id_is_rejected() {
        let (bytes, sig, pk) = signed(&manifest_json(
            "2026-08-01T00:00:00Z",
            "2026-08-15T00:00:00Z",
        ));
        let roots = [("other-root", pk.as_str())]; // manifest says rootKeyId "root"
        assert_eq!(
            verify_manifest(&bytes, &sig, &roots, "2026-08-10T00:00:00Z", None),
            Err(ManifestVerificationError::UnknownRoot)
        );
    }

    #[test]
    fn bad_signature_is_rejected() {
        let (bytes, _sig, pk) = signed(&manifest_json(
            "2026-08-01T00:00:00Z",
            "2026-08-15T00:00:00Z",
        ));
        let roots = [("root", pk.as_str())];
        let bad = STANDARD.encode([0u8; 64]);
        assert_eq!(
            verify_manifest(&bytes, &bad, &roots, "2026-08-10T00:00:00Z", None),
            Err(ManifestVerificationError::InvalidSignature)
        );
    }

    #[test]
    fn empty_roots_reject_everything() {
        let (bytes, sig, _pk) = signed(&manifest_json(
            "2026-08-01T00:00:00Z",
            "2026-08-15T00:00:00Z",
        ));
        assert_eq!(
            verify_manifest(&bytes, &sig, &[], "2026-08-10T00:00:00Z", None),
            Err(ManifestVerificationError::UnknownRoot)
        );
    }

    const MANIFEST_JSON: &str = r#"{"schema":1,"issuedAt":"2026-08-01T00:00:00Z",
      "expiresAt":"2026-08-15T00:00:00Z","rootKeyId":"cosign-root-2026",
      "publishers":[{"keyId":"cosign-registry-2026","publicKey":"AAAA","status":"active"}]}"#;

    #[test]
    fn parses_a_well_formed_manifest() {
        let m = parse_manifest(MANIFEST_JSON.as_bytes()).expect("parse");
        assert_eq!(m.schema, 1);
        assert_eq!(m.root_key_id, "cosign-root-2026");
        assert_eq!(m.issued_at, "2026-08-01T00:00:00Z");
        assert_eq!(m.publishers.len(), 1);
        assert_eq!(m.publishers[0].key_id, "cosign-registry-2026");
        assert_eq!(m.publishers[0].public_key, "AAAA");
    }

    #[test]
    fn malformed_json_parses_to_none() {
        assert!(parse_manifest(b"not json").is_none());
        assert!(parse_manifest(b"").is_none());
    }
}
