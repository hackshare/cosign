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

    @State private var networkSettings: NetworkSettingsStore
    @State private var squadsService: SquadsService?

    init() {
        let demoMode = CosignDemoMode.launchConfiguration()
        self.demoMode = demoMode
        demoFixture = demoMode.map { mode in
            CosignDemoFixture.profile(
                mode.profile,
                memberAddresses: CosignDemoSigners.memberAddresses(for: mode.profile)
            )
        }

        do {
            container = try PersistenceContainer.makeContainer()
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }

        let store = NetworkSettingsStore()
        if demoMode == nil {
            let signerCount = (try? container.mainContext.fetchCount(FetchDescriptor<RegisteredSigner>())) ?? 0
            store.resolveInitialNetwork(hasExistingSigners: signerCount > 0)
        }
        _networkSettings = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            let environment = demoFixture.map(demoEnvironment) ?? networkSettings.environment
            let service = squadsService ?? makeService(environment)
            ContentView()
                .preferredColorScheme(.dark)
                .environment(networkSettings)
                .environment(networkSettings.networkHealth)
                .environment(\.indexerEnvironment, environment)
                .environment(\.squadsService, service)
                .environment(\.cosignDemoMode, demoMode)
                .onAppear { if squadsService == nil { squadsService = service } }
                .onChange(of: networkSettings.selectedNetwork) { _, _ in
                    guard demoFixture == nil else { return }
                    squadsService = makeService(networkSettings.environment)
                }
        }
        .modelContainer(container)
    }

    private func makeService(_ environment: IndexerEnvironment) -> SquadsService {
        SquadsService(
            environment: environment,
            demoFixture: demoFixture,
            demoBroadcastMode: demoBroadcastMode(for: demoMode),
            healthReporter: networkSettings.networkHealth.reporter()
        )
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
