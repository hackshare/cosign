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
            await runWithReconnect(webSocketURL: webSocketURL, accounts: accounts)
        }
    }

    /// Keep the live subscription up across drops. `SolanaWebSocketAccountWatcher`
    /// finishes its stream on any socket error, so without this the subscription
    /// would end on the first blip and the app would sit on polling forever while
    /// the banner claims it is reconnecting. Re-subscribe with exponential backoff
    /// (reset once a connection has held long enough to count as healthy) until the
    /// enclosing task is cancelled. A successful re-subscribe reports webSocket
    /// health, which clears the paused banner.
    private func runWithReconnect(webSocketURL: URL, accounts: [String]) async {
        var backoff = WebSocketReconnectBackoff()
        let clock = ContinuousClock()

        while !Task.isCancelled {
            let connectedAt = clock.now
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

            if Task.isCancelled {
                return
            }
            let delay = backoff.nextDelay(connectedFor: connectedAt.duration(to: clock.now))
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
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
