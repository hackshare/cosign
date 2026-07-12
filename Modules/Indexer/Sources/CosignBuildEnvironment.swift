import Foundation

/// The relay environment pinned at build time (per scheme, via the
/// `CosignRelayURL` / `CosignEnvironment` Info.plist keys). When a relay URL is
/// baked in, the app is a thin client of that one verifiable endpoint — there is
/// no runtime network configuration. Absent (e.g. the demo build), the app falls
/// back to its default behaviour.
public struct CosignBuildEnvironment: Sendable {
    public let relayURL: URL?
    public let environmentName: String
    public let devnetRelayURL: URL?
    public let mainnetRelayURL: URL?

    public static func current(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> CosignBuildEnvironment {
        func url(_ key: String) -> URL? {
            let raw = (infoDictionary[key] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? nil : URL(string: raw)
        }
        let environment = (infoDictionary["CosignEnvironment"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CosignBuildEnvironment(
            relayURL: url("CosignRelayURL"),
            environmentName: environment,
            devnetRelayURL: url("CosignDevnetRelayURL"),
            mainnetRelayURL: url("CosignMainnetRelayURL")
        )
    }
}
