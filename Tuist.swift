import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        compatibleXcodeVersions: .upToNextMajor("26.0"),
        swiftVersion: .init("6.0"),
        generationOptions: .options(
            resolveDependenciesWithSystemScm: false,
            enforceExplicitDependencies: true
        )
    )
)
