import Foundation
import Observation

public enum NetworkEndpoint: Sendable {
    case rpc
    case relay
    case webSocket
}

/// A Sendable hook the network clients call from any context to report whether
/// a request to a given endpoint succeeded. Mutation hops to the main actor.
public struct NetworkHealthReporter: Sendable {
    let record: @Sendable (NetworkEndpoint, Bool) -> Void

    public func success(_ endpoint: NetworkEndpoint) {
        record(endpoint, true)
    }

    public func failure(_ endpoint: NetworkEndpoint) {
        record(endpoint, false)
    }
}

/// The dominant degraded mode. The app talks only to the relay, so any failed
/// relay or RPC request means no chain data: `offline`. WebSocket failure only
/// means live push is paused and polling has taken over. A relay-enhanced-only
/// fault with core data still live raises no status; the affected value
/// self-signals through the freshness ladder or decode confidence instead.
public enum NetworkHealthStatus: Equatable, Sendable {
    case healthy
    case webSocketDown
    case offline
}

@Observable
public final class NetworkHealth: @unchecked Sendable {
    public private(set) var status: NetworkHealthStatus = .healthy
    public private(set) var lastSuccess: Date?

    @ObservationIgnored private var rpcFailures = 0
    @ObservationIgnored private var relayFailures = 0
    @ObservationIgnored private var webSocketHealthy = true
    @ObservationIgnored private var webSocketDownConfirmed = false
    @ObservationIgnored private var webSocketGraceTask: Task<Void, Never>?

    private let failureThreshold = 2
    private let webSocketGrace: Duration

    /// - Parameter webSocketGrace: how long the websocket must stay down before
    ///   the paused banner appears. Debounces transient drops that the reconnect
    ///   loop clears almost immediately.
    public init(webSocketGrace: Duration = .seconds(4)) {
        self.webSocketGrace = webSocketGrace
    }

    /// A reporter safe to hand to clients on background actors; it marshals each
    /// outcome back to the main actor before touching observable state.
    public nonisolated func reporter() -> NetworkHealthReporter {
        NetworkHealthReporter { [weak self] endpoint, success in
            Task { @MainActor in
                self?.record(endpoint, success: success)
            }
        }
    }

    /// Clear the degraded state so the banner dismisses; the in-flight polling
    /// and WebSocket refreshes re-evaluate and re-degrade if still unreachable.
    @MainActor
    public func retry() {
        rpcFailures = 0
        relayFailures = 0
        webSocketHealthy = true
        webSocketGraceTask?.cancel()
        webSocketGraceTask = nil
        webSocketDownConfirmed = false
        recomputeStatus()
    }

    @MainActor
    private func record(_ endpoint: NetworkEndpoint, success: Bool) {
        switch endpoint {
        case .rpc:
            rpcFailures = success ? 0 : rpcFailures + 1
        case .relay:
            relayFailures = success ? 0 : relayFailures + 1
        case .webSocket:
            updateWebSocketHealth(success)
        }
        if success {
            lastSuccess = Date()
        }
        recomputeStatus()
    }

    /// A websocket failure only surfaces as `.webSocketDown` if it persists
    /// through the grace window. A success clears any pending or confirmed
    /// down state immediately.
    @MainActor
    private func updateWebSocketHealth(_ healthy: Bool) {
        webSocketHealthy = healthy
        if healthy {
            webSocketGraceTask?.cancel()
            webSocketGraceTask = nil
            webSocketDownConfirmed = false
            return
        }
        guard !webSocketDownConfirmed, webSocketGraceTask == nil else {
            return
        }
        let grace = webSocketGrace
        webSocketGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: grace)
            guard let self, !Task.isCancelled else {
                return
            }
            webSocketGraceTask = nil
            if !webSocketHealthy {
                webSocketDownConfirmed = true
                recomputeStatus()
            }
        }
    }

    @MainActor
    private func recomputeStatus() {
        if rpcFailures >= failureThreshold || relayFailures >= failureThreshold {
            status = .offline
        } else if webSocketDownConfirmed {
            status = .webSocketDown
        } else {
            status = .healthy
        }
    }
}
