import ProjectDescription

public enum TargetFactory {
    public static let bundleIdPrefix = "com.hackshare.cosign"
    public static let deploymentTarget: DeploymentTargets = .iOS("17.0")
    public static let recommendedBuildSettings: SettingsDictionary = [
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "STRING_CATALOG_GENERATE_SYMBOLS": "YES"
    ]
    public static let appBuildSettings: SettingsDictionary = recommendedBuildSettings.merging([
        "DEVELOPMENT_TEAM": "85ZZHRDM2S",
        // Defaults for the Info.plist version keys; the deploy script overrides
        // CURRENT_PROJECT_VERSION per build so TestFlight gets a unique build number.
        "MARKETING_VERSION": "0.1.0",
        "CURRENT_PROJECT_VERSION": "1"
    ])

    public static func framework(
        name: String,
        sources: SourceFilesList,
        resources: ResourceFileElements? = nil,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "\(bundleIdPrefix).\(name.lowercased())",
            deploymentTargets: deploymentTarget,
            sources: sources,
            resources: resources,
            dependencies: dependencies
        )
    }

    public static func unitTests(
        name: String,
        sources: SourceFilesList,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: "\(name)Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdPrefix).\(name.lowercased()).tests",
            deploymentTargets: deploymentTarget,
            sources: sources,
            dependencies: [.target(name: name)] + dependencies
        )
    }
}
