import Foundation

/// Reconnect backoff schedule for the live-updates websocket. Pure and
/// synchronous so the policy can be unit-tested independent of any socket.
///
/// The delay starts at `base` and doubles after each attempt up to `max`. Once a
/// connection has held for at least `healthyThreshold`, the schedule resets to
/// `base`: a link that was healthy before dropping recovers quickly, while a
/// link that keeps flapping escalates toward `max`.
public struct WebSocketReconnectBackoff: Sendable {
    public let base: Duration
    public let max: Duration
    public let healthyThreshold: Duration
    public private(set) var current: Duration

    public init(
        base: Duration = .seconds(1),
        max: Duration = .seconds(30),
        healthyThreshold: Duration = .seconds(10)
    ) {
        self.base = base
        self.max = max
        self.healthyThreshold = healthyThreshold
        current = base
    }

    /// The delay to wait before the next reconnect attempt, given how long the
    /// just-ended connection stayed up. Advances the schedule for next time.
    public mutating func nextDelay(connectedFor: Duration) -> Duration {
        if connectedFor >= healthyThreshold {
            current = base
        }
        let delay = current
        current = Swift.min(current * 2, max)
        return delay
    }
}
