import Foundation
import Provenance

extension CosignCopy {
    enum BuildVerification {
        static let screenTitle = "Build verification"

        static let verifiedTitle = "Verified"
        static let verifiedSubtitle = "Signature valid · matches this build"
        static let signedClaimSection = "Signed claim"
        static let fingerprintSection = "Fingerprint · SHA-256"
        static let openReleaseButton = "Open GitHub Release"
        static let copyFingerprintButton = "Copy fingerprint"
        static let copyClaimButton = "Copy claim"

        static let developmentTitle = "No build claim"
        static let developmentSubtitle = "Development build"
        static let developmentExplanation =
            "Build claims are embedded only in release builds signed in CI. " +
            "Local and development builds run without one. This is expected and not an error."
        static let runningBundleSection = "Running bundle · unverified"
        static let emptyValue = "—"

        static let failedTitle = "Verification failed"
        static let reasonEyebrow = "Reason"
        static let claimVsRunningSection = "Signed claim vs running"
        static let matchMarker = "✓ match"
        static let trustedMarker = "✓ trusted"
        static let untrustedMarker = "✗ untrusted"
        static let signatureUntrustedValue = "Not valid for the trusted key"
        static let copyClaimJSONButton = "Copy claim JSON"

        static let versionLabel = "Version"
        static let buildLabel = "Build"
        static let releaseLabel = "Release"
        static let commitLabel = "Commit"
        static let keyLabel = "Key"
        static let toolchainLabel = "Toolchain"
        static let signatureLabel = "Signature"

        static func claimValue(_ value: String) -> String {
            "claim \(value)"
        }

        static func runningValue(_ value: String) -> String {
            "running \(value)"
        }

        static func toolchainValue(xcode: String, sdk: String) -> String {
            "\(xcode) · \(sdk) SDK"
        }

        static func reasonLabel(_ failure: BuildProvenanceFailure) -> String {
            switch failure {
            case .buildMismatch: "Build mismatch"
            case .versionMismatch: "Version mismatch"
            case .invalidSignature: "Invalid signature"
            case .unknownKey: "Unknown signing key"
            case .malformed: "Unreadable claim"
            }
        }

        static func reasonDetail(_ failure: BuildProvenanceFailure) -> String {
            switch failure {
            case .buildMismatch:
                "The running bundle does not match the build in the signed claim. Do not trust this build."
            case .versionMismatch:
                "The running app version does not match the signed claim. Do not trust this build."
            case .invalidSignature:
                "The embedded claim's signature is not valid for the trusted key. Do not trust this build."
            case .unknownKey:
                "The claim is signed by a key this app does not trust. Do not trust this build."
            case .malformed:
                "The embedded build claim could not be read. Do not trust this build."
            }
        }
    }
}
