import Provenance
import SwiftUI

/// Demo/UITest seam for the build-verification screen. The walkthrough sets
/// `COSIGN_BV_FIXTURE` in the launched app's environment to force one of the
/// three provenance states (which otherwise need an embedded, signed claim).
///
/// Compiled out of release builds, so production reads `Bundle.main` as usual
/// and never consults the environment variable.
public enum BuildVerificationFixture {
    public static let environmentKey = "COSIGN_BV_FIXTURE"

    public static func injectedState(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BuildProvenanceState? {
        #if DEBUG
        switch environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "verified": return BuildProvenanceFixtures.verified
        case "failed": return BuildProvenanceFixtures.failedBuildMismatch
        case "development": return BuildProvenanceFixtures.development
        default: return nil
        }
        #else
        return nil
        #endif
    }
}
