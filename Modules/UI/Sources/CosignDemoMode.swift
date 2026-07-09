import CosignCore
import Foundation
import SwiftUI

public struct CosignDemoMode: Equatable, Sendable {
    public let profile: String

    public init(profile: String) {
        self.profile = profile.isEmpty ? "appstore" : profile
    }

    public static func launchConfiguration(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> CosignDemoMode? {
        #if DEBUG
        let argumentProfile = arguments.first { $0.hasPrefix("--cosign-demo=") }?.dropFirst("--cosign-demo=".count)
        if let argumentProfile, let mode = demoMode(from: String(argumentProfile)) {
            return mode
        }

        if arguments.contains("--cosign-demo") {
            return CosignDemoMode(profile: "appstore")
        }

        if let mode = demoMode(from: environment["COSIGN_DEMO_MODE"]) {
            return mode
        }
        #endif

        let configuredProfile = infoDictionary["CosignDemoModeProfile"] as? String
        if let mode = demoMode(from: configuredProfile) {
            return mode
        }

        return nil
    }

    public static func shouldResetPersistentData(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("--cosign-demo-reset")
    }

    private static func demoMode(from value: String?) -> CosignDemoMode? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "0", !trimmed.hasPrefix("$(") else {
            return nil
        }

        return CosignDemoMode(profile: trimmed == "1" ? "appstore" : trimmed)
    }

    public var disablesNetworkWrites: Bool {
        true
    }

    public var usesMarketingNetworkFooter: Bool {
        profile == "appstore"
    }
}

public extension EnvironmentValues {
    @Entry var cosignDemoMode: CosignDemoMode?
}

public extension CosignDemoMode {
    enum BroadcastFailureMode: Equatable, Sendable {
        case retryable
        case terminal
        /// Approve leg succeeds; execute leg always fails. Drives the partial-receipt path.
        case executeOnly
    }

    /// Returns the active broadcast-failure simulation mode, if any.
    ///
    /// Parsed from launch arguments. Only active in DEBUG builds; returns nil in release.
    static func broadcastFailureMode(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> BroadcastFailureMode? {
        #if DEBUG
        if arguments.contains("--broadcast-failure-terminal") { return .terminal }
        if arguments.contains("--broadcast-failure-execute-only") { return .executeOnly }
        if arguments.contains("--broadcast-failure") { return .retryable }
        #endif
        return nil
    }

    /// Seeds the signing tally for UI-test walkthroughs.
    ///
    /// Reads `--signing-tally-seed=N` and sets each signer's count to N.
    /// Only active in DEBUG builds; no-ops in release.
    static func seedSigningTallyIfRequested(signerSeeds: [CosignDemoSignerSeed]) {
        #if DEBUG
        let prefix = "--signing-tally-seed="
        guard
            let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
            let tally = Int(String(arg.dropFirst(prefix.count))),
            tally > 0
        else { return }
        for seed in signerSeeds {
            SigningTally.set(for: CosignCore.base58(seed.pubkey), count: tally)
        }
        #endif
    }

    /// Clears the signing tally for all given signer seeds.
    ///
    /// Call during demo resets so the tally starts fresh each UI-test run.
    static func resetSigningTally(signerSeeds: [CosignDemoSignerSeed]) {
        for seed in signerSeeds {
            SigningTally.reset(for: CosignCore.base58(seed.pubkey))
        }
    }
}
