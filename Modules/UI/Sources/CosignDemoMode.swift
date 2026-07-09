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

    #if DEBUG
    /// Seconds to subtract from a demo price snapshot's `fetchedAt` so UI tests
    /// can force the freshness ladder into stale (≥120 s) or expired (>900 s)
    /// without waiting for real time to elapse. Only honoured in DEBUG builds.
    public static func priceAgeSeconds(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Int? {
        let prefix = "--price-age-seconds="
        guard let arg = arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return Int(arg.dropFirst(prefix.count))
    }
    #endif

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
