import Foundation
import Testing
@testable import Indexer

struct WebSocketReconnectBackoffTests {
    private func makeBackoff() -> WebSocketReconnectBackoff {
        WebSocketReconnectBackoff(base: .seconds(1), max: .seconds(30), healthyThreshold: .seconds(10))
    }

    @Test func escalatesByDoublingWhenConnectionsFlap() {
        var backoff = makeBackoff()
        // Each drop happens before the healthy threshold, so the delay doubles.
        #expect(backoff.nextDelay(connectedFor: .zero) == .seconds(1))
        #expect(backoff.nextDelay(connectedFor: .zero) == .seconds(2))
        #expect(backoff.nextDelay(connectedFor: .zero) == .seconds(4))
        #expect(backoff.nextDelay(connectedFor: .zero) == .seconds(8))
        #expect(backoff.nextDelay(connectedFor: .zero) == .seconds(16))
    }

    @Test func capsAtMaxAndStaysThere() {
        var backoff = makeBackoff()
        var last: Duration = .zero
        for _ in 0 ..< 10 {
            last = backoff.nextDelay(connectedFor: .zero)
        }
        #expect(last == .seconds(30))
        #expect(backoff.nextDelay(connectedFor: .zero) == .seconds(30))
    }

    @Test func resetsToBaseAfterAHealthyConnection() {
        var backoff = makeBackoff()
        _ = backoff.nextDelay(connectedFor: .zero)
        _ = backoff.nextDelay(connectedFor: .zero)
        _ = backoff.nextDelay(connectedFor: .zero)
        // A connection that held past the healthy threshold resets to base,
        // then resumes doubling.
        #expect(backoff.nextDelay(connectedFor: .seconds(20)) == .seconds(1))
        #expect(backoff.nextDelay(connectedFor: .zero) == .seconds(2))
    }

    @Test func healthyThresholdIsInclusive() {
        var backoff = makeBackoff()
        _ = backoff.nextDelay(connectedFor: .zero)
        #expect(backoff.nextDelay(connectedFor: .seconds(10)) == .seconds(1))
    }
}
