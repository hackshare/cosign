import ProjectDescription
import ProjectDescriptionHelpers

let appDependencies: [TargetDependency] = [
    .target(name: "Core"),
    .target(name: "CosignCore"),
    .target(name: "Indexer"),
    .target(name: "Persistence"),
    .target(name: "Provenance"),
    .target(name: "Signers"),
    .target(name: "Squads"),
    .target(name: "UI"),
    .xcframework(path: "Modules/CosignCore/Frameworks/CosignCore.xcframework")
]

// Seals the signed BuildClaim into the app bundle before code signing. No-ops
// unless the release build passes EMBED_BUILD_CLAIM=YES and BUILD_CLAIM_DIR.
let embedBuildClaimScript: TargetScript = .post(
    script: """
    if [ "${EMBED_BUILD_CLAIM:-NO}" != "YES" ]; then exit 0; fi
    : "${BUILD_CLAIM_DIR:?BUILD_CLAIM_DIR must be set}"
    dest="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
    for f in BuildClaim.json BuildClaim.sig; do
        if [ ! -s "${BUILD_CLAIM_DIR}/${f}" ]; then echo "Missing ${BUILD_CLAIM_DIR}/${f}" >&2; exit 1; fi
        /usr/bin/install -m 0444 "${BUILD_CLAIM_DIR}/${f}" "${dest}/${f}"
    done
    """,
    name: "Embed BuildClaim",
    inputPaths: ["$(BUILD_CLAIM_DIR)/BuildClaim.json", "$(BUILD_CLAIM_DIR)/BuildClaim.sig"],
    outputPaths: [
        "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/BuildClaim.json",
        "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/BuildClaim.sig"
    ],
    basedOnDependencyAnalysis: false
)

func appBuildSettings(
    displayName: String,
    developmentURLScheme: String,
    appIconName: String,
    relayURL: String = "",
    environmentName: String = "",
    demoModeProfile: String? = nil
) -> Settings {
    let baseOverrides: SettingsDictionary = [
        "ASSETCATALOG_COMPILER_APPICON_NAME": .string(appIconName),
        "COSIGN_APP_DISPLAY_NAME": .string(displayName),
        "COSIGN_DEV_URL_SCHEME": .string(developmentURLScheme),
        "COSIGN_DEMO_MODE_PROFILE": .string(demoModeProfile ?? ""),
        "COSIGN_RELAY_URL": .string(relayURL),
        "COSIGN_ENV": .string(environmentName),
        "EMBED_BUILD_CLAIM": "NO"
    ]
    let base = TargetFactory.appBuildSettings.merging(baseOverrides)

    let debugInfoPlistDefinitions = demoModeProfile == nil ? "DEBUG=1" : "DEBUG=1 COSIGN_DEMO=1"
    let releaseInfoPlistDefinitions = demoModeProfile == nil ? "" : "COSIGN_DEMO=1"
    let debugSettings: SettingsDictionary = [
        "GCC_PREPROCESSOR_DEFINITIONS": "$(inherited) DEBUG=1",
        "INFOPLIST_PREPROCESS": "YES",
        "INFOPLIST_PREPROCESSOR_DEFINITIONS": .string(debugInfoPlistDefinitions)
    ]
    let releaseSettings: SettingsDictionary = [
        "INFOPLIST_PREPROCESS": "YES",
        "INFOPLIST_PREPROCESSOR_DEFINITIONS": .string(releaseInfoPlistDefinitions)
    ]

    return .settings(base: base, configurations: [
        .debug(
            name: "Debug",
            settings: debugSettings
        ),
        .release(
            name: "Release",
            settings: releaseSettings
        )
    ])
}

func appTarget(
    name: String,
    bundleId: String,
    displayName: String,
    developmentURLScheme: String,
    appIconName: String,
    relayURL: String = "",
    environmentName: String = "",
    demoModeProfile: String? = nil
) -> Target {
    .target(
        name: name,
        destinations: [.iPhone],
        product: .app,
        bundleId: bundleId,
        deploymentTargets: TargetFactory.deploymentTarget,
        infoPlist: .file(path: "App/Resources/Info.plist"),
        sources: ["App/Sources/**"],
        resources: ["App/Resources/Assets.xcassets"],
        entitlements: .file(path: "App/Resources/Cosign.entitlements"),
        scripts: [embedBuildClaimScript],
        dependencies: appDependencies,
        settings: appBuildSettings(
            displayName: displayName,
            developmentURLScheme: developmentURLScheme,
            appIconName: appIconName,
            relayURL: relayURL,
            environmentName: environmentName,
            demoModeProfile: demoModeProfile
        )
    )
}

let project = Project(
    name: "Cosign",
    options: .options(
        automaticSchemesOptions: .enabled(targetSchemesGrouping: .byNameSuffix(
            build: ["Implementation", "Interface", "Mocks", "Testing"],
            test: ["Tests", "IntegrationTests", "UITests", "SnapshotTests"],
            run: ["App", "Example"]
        )),
        developmentRegion: "en"
    ),
    packages: [
        .remote(
            url: "https://github.com/Yubico/yubikit-swift.git",
            requirement: .upToNextMajor(from: "1.3.0")
        )
    ],
    targets: [
        // CosignCore: thin Swift wrapper around the UniFFI-generated bindings,
        // which are emitted into Modules/CosignCore/Sources/Generated/ by
        // scripts/build-xcframework.sh. The XCFramework provides the underlying
        // cosign_coreFFI C module that the generated Swift file imports.
        TargetFactory.framework(
            name: "CosignCore",
            sources: ["Modules/CosignCore/Sources/**"],
            dependencies: [
                .xcframework(path: "Modules/CosignCore/Frameworks/CosignCore.xcframework")
            ]
        ),
        TargetFactory.unitTests(
            name: "CosignCore",
            sources: ["Modules/CosignCore/Tests/**"]
        ),

        // Core: pure Swift types and protocols, no Solana dependency.
        TargetFactory.framework(
            name: "Core",
            sources: ["Modules/Core/Sources/**"]
        ),
        TargetFactory.unitTests(
            name: "Core",
            sources: ["Modules/Core/Tests/**"]
        ),

        // Provenance: CryptoKit verification of the embedded signed BuildClaim.
        TargetFactory.framework(
            name: "Provenance",
            sources: ["Modules/Provenance/Sources/**"]
        ),
        TargetFactory.unitTests(
            name: "Provenance",
            sources: ["Modules/Provenance/Tests/**"]
        ),

        // Indexer: Swift clients for Helius DAS and optional relay integration.
        TargetFactory.framework(
            name: "Indexer",
            sources: ["Modules/Indexer/Sources/**"],
            dependencies: [.target(name: "Core")]
        ),
        TargetFactory.unitTests(
            name: "Indexer",
            sources: ["Modules/Indexer/Tests/**"],
            dependencies: [.target(name: "Core")]
        ),

        // Persistence: SwiftData models.
        TargetFactory.framework(
            name: "Persistence",
            sources: ["Modules/Persistence/Sources/**"],
            dependencies: [.target(name: "Core")]
        ),
        TargetFactory.unitTests(
            name: "Persistence",
            sources: ["Modules/Persistence/Tests/**"],
            dependencies: [.target(name: "Core")]
        ),

        // Signers: hot wallets and external signing device integrations.
        TargetFactory.framework(
            name: "Signers",
            sources: ["Modules/Signers/Sources/**"],
            dependencies: [
                .target(name: "Core"),
                .target(name: "CosignCore"),
                .package(product: "YubiKit")
            ]
        ),
        TargetFactory.unitTests(
            name: "Signers",
            sources: ["Modules/Signers/Tests/**"],
            dependencies: [
                .target(name: "Core"),
                .target(name: "CosignCore"),
                .xcframework(path: "Modules/CosignCore/Frameworks/CosignCore.xcframework")
            ]
        ),

        // Squads: protocol-specific orchestration over the Rust core and Indexer.
        TargetFactory.framework(
            name: "Squads",
            sources: ["Modules/Squads/Sources/**"],
            dependencies: [
                .target(name: "Core"),
                .target(name: "CosignCore"),
                .target(name: "Indexer")
            ]
        ),
        TargetFactory.unitTests(
            name: "Squads",
            sources: ["Modules/Squads/Tests/**"],
            dependencies: [
                .target(name: "Core"),
                .target(name: "CosignCore"),
                .target(name: "Indexer"),
                .xcframework(path: "Modules/CosignCore/Frameworks/CosignCore.xcframework")
            ]
        ),

        // UI: SwiftUI views. SWIFT_EMIT_LOC_STRINGS extracts this module's
        // String(localized:) calls into Localizable.xcstrings at build time.
        TargetFactory.framework(
            name: "UI",
            sources: ["Modules/UI/Sources/**"],
            resources: ["Modules/UI/Resources/**"],
            dependencies: [
                .target(name: "Core"),
                .target(name: "CosignCore"),
                .target(name: "Indexer"),
                .target(name: "Persistence"),
                .target(name: "Provenance"),
                .target(name: "Signers"),
                .target(name: "Squads")
            ],
            settings: .settings(base: ["SWIFT_EMIT_LOC_STRINGS": "YES"])
        ),

        // The iOS app. Note: also depends directly on the CosignCore.xcframework
        // because the CosignCore Swift module re-exports types from the
        // cosign_coreFFI Clang module, and Swift requires that consumer targets
        // can resolve all transitively-referenced modules at compile time.
        // Each non-demo build is pinned to one environment's relay — the app is a
        // thin, verifiable client of that single endpoint. Replace the relayURL
        // values below with the deployed relay hosts before shipping.
        // TEMPORARY: the mainnet-bundle-id `Cosign` target ships devnet content for
        // the first TestFlight build (to claim com.hackshare.cosign now). It uses
        // the ribboned devnet icon so testers can tell. Switch relayURL /
        // environmentName / appIconName back to mainnet (+ "AppIcon") when shipping
        // mainnet; `CosignDevnet` (com.hackshare.cosign.devnet) is the separate
        // devnet release.
        appTarget(
            name: "Cosign",
            bundleId: TargetFactory.bundleIdPrefix,
            displayName: "Cosign",
            developmentURLScheme: "cosign-dev",
            appIconName: "AppIconDevnet",
            relayURL: "https://cosign-relay-devnet.fly.dev",
            environmentName: "devnet"
        ),
        appTarget(
            name: "CosignDevnet",
            bundleId: "\(TargetFactory.bundleIdPrefix).devnet",
            displayName: "Cosign Devnet",
            developmentURLScheme: "cosign-devnet-dev",
            appIconName: "AppIconDevnet",
            relayURL: "https://cosign-relay-devnet.fly.dev",
            environmentName: "devnet"
        ),
        appTarget(
            name: "CosignDemo",
            bundleId: "\(TargetFactory.bundleIdPrefix).demo",
            displayName: "Cosign Demo",
            developmentURLScheme: "cosign-demo-dev",
            appIconName: "AppIconDemo",
            demoModeProfile: "appstore"
        ),
        .target(
            name: "CosignDemoUITests",
            destinations: [.iPhone],
            product: .uiTests,
            bundleId: "\(TargetFactory.bundleIdPrefix).demo.uitests",
            deploymentTargets: TargetFactory.deploymentTarget,
            sources: ["UITests/Sources/**"],
            dependencies: [.target(name: "CosignDemo")],
            settings: .settings(base: TargetFactory.appBuildSettings)
        )
    ]
)
