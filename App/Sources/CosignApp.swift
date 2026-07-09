import Indexer
import Persistence
import Squads
import SwiftData
import SwiftUI
import UI

@main
struct CosignApp: App {
    let container: ModelContainer
    let demoMode: CosignDemoMode?
    let demoFixture: CosignDemoFixture?

    @State private var networkSettings = NetworkSettingsStore()

    init() {
        let demoMode = CosignDemoMode.launchConfiguration()
        self.demoMode = demoMode
        demoFixture = demoMode.map { demoMode in
            CosignDemoFixture.profile(
                demoMode.profile,
                memberAddresses: CosignDemoSigners.memberAddresses(for: demoMode.profile)
            )
        }

        do {
            container = try PersistenceContainer.makeContainer()
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            let environment = demoFixture.map(demoEnvironment) ?? networkSettings.environment

            ContentView()
                .preferredColorScheme(.dark)
                .environment(networkSettings)
                .environment(networkSettings.networkHealth)
                .environment(\.indexerEnvironment, environment)
                .environment(\.squadsService, SquadsService(
                    environment: environment,
                    demoFixture: demoFixture,
                    demoBroadcastMode: demoBroadcastMode(for: demoMode),
                    healthReporter: networkSettings.networkHealth.reporter()
                ))
                .environment(\.cosignDemoMode, demoMode)
        }
        .modelContainer(container)
    }

    private func demoEnvironment(fixture: CosignDemoFixture) -> IndexerEnvironment {
        IndexerEnvironment(
            rpcURL: URL(string: "https://demo.cosign.local")!,
            relay: DemoRelayClient(fixture: fixture),
            webSocketURL: nil,
            explorerRPCURL: IndexerEnvironment.devnetRPCURL
        )
    }

    private func demoBroadcastMode(for mode: CosignDemoMode?) -> DemoBroadcastMode? {
        guard mode != nil else { return nil }
        switch CosignDemoMode.broadcastFailureMode() {
        case .retryable: return .retryable
        case .terminal: return .terminal
        case .executeOnly: return .executeOnly
        case nil: return nil
        }
    }
}
