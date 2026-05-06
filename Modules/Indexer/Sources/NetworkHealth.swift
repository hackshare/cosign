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
/// relay/RPC request means no chain data — `offline`. WebSocket failure only
/// means live push is paused and polling has taken over.
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

    private let failureThreshold = 2

    public init() {}

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
            webSocketHealthy = success
        }
        if success {
            lastSuccess = Date()
        }
        recomputeStatus()
    }

    @MainActor
    private func recomputeStatus() {
        if rpcFailures >= failureThreshold || relayFailures >= failureThreshold {
            status = .offline
        } else if !webSocketHealthy {
            status = .webSocketDown
        } else {
            status = .healthy
        }
    }
}
