import Foundation
import Provenance

extension CosignCopy {
    enum BuildVerification {
        static let screenTitle = String(localized: "Build verification", bundle: .module)

        static let verifiedTitle = String(localized: "Verified", bundle: .module)
        static let verifiedSubtitle = String(localized: "Signature valid · matches this build", bundle: .module)
        static let signedClaimSection = String(localized: "Signed claim", bundle: .module)
        static let fingerprintSection = String(localized: "Fingerprint · SHA-256", bundle: .module)
        static let openReleaseButton = String(localized: "Open GitHub Release", bundle: .module)
        static let copyFingerprintButton = String(localized: "Copy fingerprint", bundle: .module)
        static let copyClaimButton = String(localized: "Copy claim", bundle: .module)

        static let developmentTitle = String(localized: "No build claim", bundle: .module)
        static let developmentSubtitle = String(localized: "Development build", bundle: .module)
        static let developmentExplanation =
            String(
                localized: "Build claims are embedded only in release builds signed in CI. Local and development builds run without one. This is expected and not an error.",
                bundle: .module
            )
        static let runningBundleSection = String(localized: "Running bundle · unverified", bundle: .module)
        static let emptyValue = String(localized: "—", bundle: .module)

        static let failedTitle = String(localized: "Verification failed", bundle: .module)
        static let reasonEyebrow = String(localized: "Reason", bundle: .module)
        static let claimVsRunningSection = String(localized: "Signed claim vs running", bundle: .module)
        static let matchMarker = String(localized: "✓ match", bundle: .module)
        static let trustedMarker = String(localized: "✓ trusted", bundle: .module)
        static let untrustedMarker = String(localized: "✗ untrusted", bundle: .module)
        static let signatureUntrustedValue = String(localized: "Not valid for the trusted key", bundle: .module)
        static let copyClaimJSONButton = String(localized: "Copy claim JSON", bundle: .module)

        static let versionLabel = String(localized: "Version", bundle: .module)
        static let buildLabel = String(localized: "Build", bundle: .module)
        static let releaseLabel = String(localized: "Release", bundle: .module)
        static let commitLabel = String(localized: "Commit", bundle: .module)
        static let keyLabel = String(localized: "Key", bundle: .module)
        static let toolchainLabel = String(localized: "Toolchain", bundle: .module)
        static let signatureLabel = String(localized: "Signature", bundle: .module)

        static func claimValue(_ value: String) -> String {
            String(localized: "claim \(value)", bundle: .module)
        }

        static func runningValue(_ value: String) -> String {
            String(localized: "running \(value)", bundle: .module)
        }

        static func toolchainValue(xcode: String, sdk: String) -> String {
            String(localized: "\(xcode) · \(sdk) SDK", bundle: .module)
        }

        static func reasonLabel(_ failure: BuildProvenanceFailure) -> String {
            switch failure {
            case .buildMismatch: String(localized: "Build mismatch", bundle: .module)
            case .versionMismatch: String(localized: "Version mismatch", bundle: .module)
            case .invalidSignature: String(localized: "Invalid signature", bundle: .module)
            case .unknownKey: String(localized: "Unknown signing key", bundle: .module)
            case .malformed: String(localized: "Unreadable claim", bundle: .module)
            }
        }

        static func reasonDetail(_ failure: BuildProvenanceFailure) -> String {
            switch failure {
            case .buildMismatch:
                String(
                    localized: "The running bundle does not match the build in the signed claim. Do not trust this build.",
                    bundle: .module
                )
            case .versionMismatch:
                String(
                    localized: "The running app version does not match the signed claim. Do not trust this build.",
                    bundle: .module
                )
            case .invalidSignature:
                String(
                    localized: "The embedded claim's signature is not valid for the trusted key. Do not trust this build.",
                    bundle: .module
                )
            case .unknownKey:
                String(
                    localized: "The claim is signed by a key this app does not trust. Do not trust this build.",
                    bundle: .module
                )
            case .malformed:
                String(
                    localized: "The embedded build claim could not be read. Do not trust this build.",
                    bundle: .module
                )
            }
        }
    }
}
