import Foundation

public struct BuildClaim: Decodable, Equatable, Sendable {
    public let schema: Int
    public let keyId: String
    public let repository: String
    public let tag: String
    public let tagObjectSha: String
    public let commitSha: String
    public let version: String
    public let build: String
    public let dependencyLockRoot: String
    public let buildRecipeSha256: String
    public let toolchain: Toolchain

    public struct Toolchain: Decodable, Equatable, Sendable {
        public let macOSProductVersion: String
        public let macOSBuild: String
        public let xcode: String
        public let swift: String
        public let iphoneOSSDK: String
    }
}

public enum BuildClaimPublicKeys {
    /// Curve25519 public keys keyed by `keyId`. The `-test` key signs unit-test
    /// fixtures; the production release key signs shipped builds.
    public static let all: [String: String] = [
        "cosign-release-2026-06": "V99YmQg2krYfN56jBVR/UeiwSZ/mjjyTcHo9PSufPpY=",
        "cosign-release-test": "u+zoVsfzqw2BKwghUGsnIAfRuotyALnvF+LiF+qZW/Y="
    ]
}
