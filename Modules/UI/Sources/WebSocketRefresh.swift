import Foundation
import Indexer
import SwiftUI

extension View {
    func webSocketRefresh(
        id: String,
        webSocketURL: URL?,
        accounts: [String],
        enabled: Bool = true,
        debounce: Duration = .milliseconds(500),
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
        modifier(WebSocketRefreshModifier(
            id: id,
            webSocketURL: webSocketURL,
            accounts: accounts,
            enabled: enabled,
            debounce: debounce,
            action: action
        ))
    }
}

private struct WebSocketRefreshModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NetworkHealth.self) private var networkHealth: NetworkHealth?

    let id: String
    let webSocketURL: URL?
    let accounts: [String]
    let enabled: Bool
    let debounce: Duration
    let action: @MainActor @Sendable () async -> Void

    func body(content: Content) -> some View {
        content.task(id: taskID) {
            let accounts = activeAccounts
            guard
                enabled,
                scenePhase == .active,
                let webSocketURL,
                !accounts.isEmpty
            else {
                return
            }

            let notifications = SolanaWebSocketAccountWatcher.notifications(
                webSocketURL: webSocketURL,
                accounts: accounts,
                healthReporter: networkHealth?.reporter()
            )
            for await _ in notifications {
                do {
                    try await Task.sleep(for: debounce)
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }
                await action()
            }
        }
    }

    private var activeAccounts: [String] {
        Array(Set(accounts.filter { !$0.isEmpty })).sorted()
    }

    private var taskID: String {
        [
            id,
            scenePhase.description,
            String(enabled),
            webSocketURL?.absoluteString ?? "none",
            activeAccounts.joined(separator: ",")
        ].joined(separator: "|")
    }
}

private extension ScenePhase {
    var description: String {
        switch self {
        case .active:
            "active"
        case .inactive:
            "inactive"
        case .background:
            "background"
        @unknown default:
            "unknown"
        }
    }
}
