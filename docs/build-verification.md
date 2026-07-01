# Build verification

Cosign release builds carry a cryptographically signed record of exactly which
source they were built from. You can verify it two ways: on device, under
**Settings → Build verification**, and externally, against the artifacts
published with each GitHub Release.

## What the app checks (on device)

Every release build embeds two files, sealed into the app bundle before Apple
code-signs it:

- `BuildClaim.json` — the build's identity (see below), serialized deterministically.
- `BuildClaim.sig` — a detached signature over those exact bytes.

On the Build verification screen the app:

1. Loads the embedded claim and signature.
2. Selects the trusted public key by the claim's `keyId`. The key is compiled
   into the app; the app never holds a private key.
3. Verifies the Curve25519 signature over the exact claim bytes.
4. Confirms the claim's `version` and `build` match the running bundle
   (`CFBundleShortVersionString` and `CFBundleVersion`).
5. Computes and shows the SHA-256 fingerprint of the claim.

It shows **Verified** only when every check passes. If a check fails it shows the
specific reason: invalid signature, unknown signing key, version mismatch, or
build mismatch. A local or development build has no embedded claim, so it shows
**No build claim (development build)**. That is expected, not an error.

## What is in a build claim

`BuildClaim.json` records:

- `version`, `build` — the app version and build number.
- `tag`, `commitSha` — the release tag and the exact source commit.
- `dependencyLockRoot` — a hash over the locked dependency set (`Cargo.lock` and
  the Swift `Package.resolved`).
- `buildRecipeSha256` — a hash over the files that define the build.
- `keyId` — which public key verifies the signature.
- `toolchain` — the macOS, Xcode, Swift, and SDK versions used.

## How a release is produced

Releases are built by a tag-triggered GitHub Actions workflow
(`.github/workflows/release.yml`), so the build runs in the open. Pushing a
signed `v<version>+<build>` tag (via `scripts/release-tag.sh`) starts it. The
workflow:

1. Confirms through GitHub that the tag is annotated and its signature is valid
   and from the trusted release signer, and that it points at the commit that
   triggered the run.
2. Builds the Rust core, generates the deterministic `BuildClaim.json`
   (`ci/create_build_claim.py`), and signs it with the release key held in a
   protected GitHub environment secret.
3. Archives the app with the claim embedded (a run-script seals it before code
   signing), then asserts the embedded files match and the code signature is
   valid.
4. Uploads the exact IPA to TestFlight.
5. Publishes a GitHub Release with `BuildClaim.{json,sig}`, a signed submission
   receipt, `SHA256SUMS`, and a verification artifact, and attaches a GitHub
   build-provenance attestation for that artifact.

The signing key is Curve25519. The private key never leaves the protected
environment; only the matching public key is compiled into the app
(`BuildClaimPublicKeys`, keyed by `keyId`), so the app verifies without holding a
secret. `scripts/deploy-testflight.sh` runs the same generate, sign, embed, and
assert chain locally for development or manual releases.

## How to verify a release yourself

For any release, the fingerprint the app shows must match the published claim:

```
gh release download 'v<version>+<build>' --repo hackshare/cosign
shasum -a 256 BuildClaim.json          # must equal the app's fingerprint
shasum -a 256 -c SHA256SUMS            # all release assets intact
gh attestation verify 'Cosign-v<version>+<build>-verification.zip' --repo hackshare/cosign
```

The attestation confirms the verification artifact was produced by this
repository's release workflow. `Tools/VerifyBuildClaim.swift` checks a claim's
signature against a public key outside the app.

## Tools

- `Tools/GenerateBuildClaimKey.swift` — generate a release key pair.
- `Tools/SignBuildClaim.swift` — sign a claim.
- `Tools/VerifyBuildClaim.swift` — verify a claim against a public key.

## What this proves, and what it does not

It proves the running build carries a claim signed by the holder of the release
key, that the claim's version and build match the app, and, through the published
claim and the GitHub attestation, that the same claim and verification artifact
were produced by this repository's workflow. Because the claim is sealed inside
the Apple-signed bundle, it cannot be swapped after signing without invalidating
that signature.

It does not, on its own, prove that Apple's delivered binary is byte-for-byte
identical to the published build. The in-app "Verified" state is still
self-reported: a malicious binary could draw the same screen. Reproducible dual
builds, where two independent builders produce matching normalized bundles, are
the remaining step that would close that gap, and are a planned next step.
