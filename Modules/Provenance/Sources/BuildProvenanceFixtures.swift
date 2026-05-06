#if DEBUG
import Foundation

/// Design-only fixtures for the three build-verification screen states. Compiled
/// out of release builds; used by `#Preview`s and the demo/UITest fixture seam to
/// render `.verified` and `.failed` without an embedded, signed `BuildClaim`.
public enum BuildProvenanceFixtures {
    public static let verifiedClaim = BuildClaim(
        schema: 1,
        keyId: "cosign-release-2026-06",
        repository: "hackshare/cosign-ios",
        tag: "v0.1.0+1751312345",
        tagObjectSha: "7d3b1f0a9c2e4d6b8a0f1c3e5d7b9a2c4e6f8d0b",
        commitSha: "aca62f4c2b1e9d7a3f5c8b2e1d4a6f9c0b3e5d7a",
        version: "0.1.0",
        build: "1751312345",
        dependencyLockRoot: "f1c3e5d7b9a2c4e6f8d0b2a4c6e8f0d2b4a6c8e0",
        buildRecipeSha256: "3c9b8d1e6f4a2c7e0d5b9f3a1c6e8d4b7a0f2c5e9d1b6a3f8c4e7d0b2a5f9c3e1",
        toolchain: BuildClaim.Toolchain(
            macOSProductVersion: "15.5",
            macOSBuild: "24F74",
            xcode: "16.4 (16F6)",
            swift: "6.1",
            iphoneOSSDK: "18.5"
        )
    )

    public static let verifiedFingerprint =
        "b7e23ec29af22b0b4e41da31e868d57226121c84e4f7c1a2b9d6e0f3a5c8d1b4"

    public static let verified = BuildProvenanceState.verified(
        VerifiedBuildClaim(claim: verifiedClaim, fingerprint: verifiedFingerprint)
    )

    /// A signed claim whose build number no longer matches the running bundle —
    /// the classic "this binary was tampered with after signing" failure.
    public static let failedBuildMismatch = BuildProvenanceState.failed(
        .buildMismatch,
        claim: verifiedClaim,
        running: RunningBundle(version: "0.1.0", build: "1751299981")
    )

    public static let development = BuildProvenanceState.developmentBuild(
        running: RunningBundle(version: "0.1.0", build: "1751312345")
    )
}
#endif
