import Foundation

public struct RunningBundle: Equatable, Sendable {
    public let version: String?
    public let build: String?
    public init(version: String?, build: String?) {
        self.version = version
        self.build = build
    }

    public static func current(_ bundle: Bundle = .main) -> RunningBundle {
        RunningBundle(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}

public enum BuildProvenanceFailure: Equatable, Sendable {
    case invalidSignature
    case unknownKey
    case versionMismatch
    case buildMismatch
    case malformed
}

public enum BuildProvenanceState: Sendable {
    case verified(VerifiedBuildClaim)
    case developmentBuild(running: RunningBundle)
    case failed(BuildProvenanceFailure, claim: BuildClaim?, running: RunningBundle)
}

public extension BuildClaimVerifier {
    static func provenanceState(bundle: Bundle = .main) -> BuildProvenanceState {
        let running = RunningBundle.current(bundle)
        guard let claimURL = bundle.url(forResource: "BuildClaim", withExtension: "json"),
              let sigURL = bundle.url(forResource: "BuildClaim", withExtension: "sig"),
              let claimData = try? Data(contentsOf: claimURL),
              let signature = try? String(contentsOf: sigURL, encoding: .utf8)
        else { return .developmentBuild(running: running) }
        do {
            return try .verified(verify(
                claimData: claimData,
                signatureBase64: signature,
                bundleVersion: running.version,
                bundleBuild: running.build
            ))
        } catch {
            let claim = try? JSONDecoder().decode(BuildClaim.self, from: claimData)
            let failure: BuildProvenanceFailure
            switch error as? BuildClaimVerificationError {
            case .some(.missingResource): return .developmentBuild(running: running)
            case .some(.unknownKey): failure = .unknownKey
            case .some(.invalidSignature): failure = .invalidSignature
            case .some(.versionMismatch): failure = .versionMismatch
            case .some(.buildMismatch): failure = .buildMismatch
            default: failure = .malformed
            }
            return .failed(failure, claim: claim, running: running)
        }
    }
}
